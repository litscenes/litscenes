import SwiftUI

/// THE GUIDED STAGE: with zero Scenes the hero stage is the journey surface.
/// One state, one primary action — Open Story, Plan Frames, art-direct the
/// focused planned frame, or start the first Scene — with a filmstrip of the
/// plan beneath. Planned frames live HERE, not in the pool: a plan is an
/// intention to art-direct, never placeable material and never a spinner.
/// The moment a Scene exists the stage returns to SceneBoxView and this view
/// is gone (`.normalStage` is the owner's branch, never rendered here).
///
/// THE GILDED PLATE LOOK: the stage is a lit plate in a dark room. The panel
/// is an explicit dark surface (`archiveWell`); the focused planned frame is
/// true cream plate stock in the Frame Creator's engraved-plate language,
/// with brass reserved for gilding and the single filled action. Accent
/// swatches come from the Scene Plan's own palette, so each project's stage
/// carries its film's colors. Dumb by design — values in, closures out;
/// every action rides an existing engine path and nothing here ever spends
/// on its own.
struct ScenesV2StageSpotlightView: View {
    let state: ScenesV2StageSpotlightState
    /// Story chapter chips (≤4 rendered) from `scenesV2StoryChapterTitles`.
    var chapterTitles: [String] = []
    /// Fulfillment candidates in plan order (`scenesV2PlannedFramesInPlanOrder`).
    var plannedFrames: [ProjectLensHeroImage] = []
    /// Rendered (ready, non-disabled) frames of the newest version, in order.
    var renderedFrames: [ProjectLensHeroImage] = []
    /// Genuinely in-flight takes — the filmstrip keeps their honest spinner.
    var generatingFrames: [ProjectLensHeroImage] = []
    /// The Scene Plan's accent swatches (`scenesV2StageAccentSwatches`).
    var accentSwatches: [LensColorSwatch] = []
    var planningTitle: String = ""
    var planningDetail: String = ""
    /// First engine blocker while Plan Frames must refuse; "" when clear.
    var planBlockedReason: String = ""
    /// A quiet secondary line when the Story moved past the plan (nil when fresh).
    var staleNote: (text: String, action: ScenesV2PlanStaleAction)? = nil
    var onRefreshSuggestions: () -> Void = {}
    var onPlanMoreFrames: () -> Void = {}
    var onOpenStory: () -> Void = {}
    var onPlanFrames: () -> Void = {}
    var onArtDirect: (ProjectLensHeroImage) -> Void = { _ in }
    /// One paid render with the plan's defaults — the plate's primary verb.
    var onRender: (ProjectLensHeroImage) -> Void = { _ in }
    /// "<stack> · <price>" beneath RENDER, and the honest reason it is refused.
    var renderCaption: String = ""
    var renderBlockReason: String = ""
    /// Roster names by character id, so a sheet-driven suggestion can say whose it is.
    var characterNamesById: [String: String] = [:]
    /// THE WAY IN: with nothing suggested and no character able to drive
    /// suggestions, the empty plate points to CHARACTERS.
    var showsCreateCharacterNotice: Bool = false
    var suggestDisabledReason: String = ""
    var onOpenCharacters: () -> Void = {}
    var onSuggestFrames: () -> Void = {}
    var onStartFirstScene: () -> Void = {}
    var onCreateFrame: () -> Void = {}
    var onOpenFrame: (ProjectLensHeroImage) -> Void = { _ in }

    /// The stepper's pick; falls back to the state's focus, then plan #1.
    @State private var focusedImageId = ""

    var body: some View {
        Group {
            switch state {
            case .storyNotReady:
                guidancePane(
                    icon: "text.book.closed",
                    title: "Make a film from your Story",
                    line: "Import media, shape the Story, and a Scene Plan of Frames is drafted for you to art-direct into Scenes.",
                    pillTitle: "OPEN STORY",
                    pillIcon: "arrow.right",
                    pillAction: onOpenStory
                )
            case .readyToPlan(let retry):
                guidancePane(
                    icon: "wand.and.stars",
                    title: retry ? "Frame planning failed — try again" : "Your Story is ready to plan",
                    line: "Plan Frames drafts a set of Frames from the saved Story — you art-direct and render each one from right here.",
                    pillTitle: retry ? "RETRY PLAN" : "PLAN FRAMES",
                    pillDisabledReason: planBlockedReason,
                    pillAction: onPlanFrames
                )
            case .planning(let refresh):
                planningPane(refresh: refresh)
            case .emptyPlan:
                if showsCreateCharacterNotice {
                    guidancePane(
                        icon: "person.crop.rectangle",
                        title: "Frames come from your characters",
                        line: scenesV2CreateCharacterNotice,
                        pillTitle: "OPEN CHARACTERS",
                        pillIcon: "arrow.right",
                        pillAction: onOpenCharacters
                    )
                } else {
                    guidancePane(
                        icon: "sparkles",
                        title: "No Frames suggested yet",
                        line: "SUGGEST FRAMES drafts two dramatic moments for every character with a sheet or source images — a text call, no image renders. Or make a Frame from scratch below.",
                        pillTitle: "SUGGEST FRAMES",
                        pillIcon: "sparkles",
                        pillDisabledReason: suggestDisabledReason,
                        pillAction: onSuggestFrames
                    )
                }
            case .artDirect, .startFirstScene:
                spotlight
            case .normalStage:
                // The owner branches to SceneBoxView long before this view
                // exists — render nothing rather than lie.
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(CanonColor.archiveWell)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(CanonColor.hairlineDark, lineWidth: 1)
        )
    }

    // MARK: Simple panes

    private func guidancePane(
        icon: String,
        title: String,
        line: String,
        pillTitle: String,
        pillIcon: String = "arrow.up.right",
        pillDisabledReason: String = "",
        pillAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(CanonColor.brass.opacity(0.8))
            Text(title)
                .font(CanonType.display(19, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
                .multilineTextAlignment(.center)
            Text(line)
                .font(CanonType.interface(11.5))
                .foregroundStyle(CanonColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .fixedSize(horizontal: false, vertical: true)
            StageBrassPill(
                title: pillTitle,
                icon: pillIcon,
                disabledReason: pillDisabledReason,
                action: pillAction
            )
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.vertical, 20)
    }

    private func planningPane(refresh: Bool) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
                .tint(CanonColor.brass)
            Text(refresh ? "Refreshing your Frames for the new Story…" : "Planning your Frames…")
                .font(CanonType.display(19, weight: .semibold))
                .foregroundStyle(CanonColor.bone)
            if !planningStatusLine.isEmpty {
                Text(planningStatusLine)
                    .font(CanonType.interface(11.5))
                    .foregroundStyle(CanonColor.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.vertical, 20)
    }

    /// THE STALE NOTE ROW: secondary by construction — archive caps and a plain
    /// brass text button; the brass pill stays the page's one primary action.
    @ViewBuilder
    private var staleNoteRow: some View {
        if let staleNote {
            HStack(spacing: 10) {
                Text(staleNote.text.uppercased())
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(CanonColor.muted)
                staleNoteAction(staleNote.action)
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func staleNoteAction(_ action: ScenesV2PlanStaleAction) -> some View {
        switch action {
        case .quiet:
            EmptyView()
        case .refreshSuggestions:
            staleNoteButton("REFRESH SUGGESTIONS", action: onRefreshSuggestions)
        case .planMoreFrames:
            staleNoteButton("PLAN MORE FRAMES", action: onPlanMoreFrames)
        }
    }

    private func staleNoteButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(CanonType.archive(7.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(CanonColor.brass)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var planningStatusLine: String {
        [planningTitle.trimmed, planningDetail.trimmed]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
    }

    // MARK: The spotlight (artDirect / startFirstScene)

    private var isStartFirstScene: Bool {
        if case .startFirstScene = state { return true }
        return false
    }

    private var focusedPlan: ProjectLensHeroImage? {
        if let match = plannedFrames.first(where: { $0.imageId == focusedImageId }) {
            return match
        }
        if case .artDirect(let focusId) = state,
           let match = plannedFrames.first(where: { $0.imageId == focusId }) {
            return match
        }
        return plannedFrames.first
    }

    private var totalPlanCount: Int {
        plannedFrames.count + renderedFrames.count + generatingFrames.count
    }

    private var spotlight: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text(isStartFirstScene ? "READY TO BUILD YOUR FIRST SCENE" : "YOUR PLAN WANTS ITS FIRST FRAME")
                    .font(CanonType.archive(8.5, weight: .bold))
                    .kerning(2.0)
                    .foregroundStyle(CanonColor.brass)
                    .layoutPriority(1)
                Rectangle()
                    .fill(CanonColor.hairlineDark)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                planTickRow
                Text("\(renderedFrames.count) OF \(totalPlanCount)")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(0.6)
                    .foregroundStyle(CanonColor.muted)
                    .layoutPriority(1)
            }
            staleNoteRow
            if !chapterTitles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(chapterTitles.prefix(4).enumerated()), id: \.offset) { index, title in
                        Text("\(index + 1) · \(title)")
                            .font(CanonType.archive(8, weight: .medium))
                            .kerning(0.5)
                            .foregroundStyle(CanonColor.muted)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .overlay(Capsule().stroke(CanonColor.hairlineDark, lineWidth: 1))
                    }
                }
            }
            HStack(alignment: .top, spacing: 18) {
                if isStartFirstScene {
                    renderedPlate
                    startFirstScenePane
                } else if let plan = focusedPlan {
                    plannedPlate(plan)
                    artDirectPane(plan)
                }
            }
            .padding(.top, 2)
            filmstrip
        }
        .padding(16)
    }

    /// One tick per plan member: rendered = brass, in-flight = softGold,
    /// planned = hollow. The kicker row's honest progress at a glance.
    @ViewBuilder
    private var planTickRow: some View {
        if totalPlanCount > 0, totalPlanCount <= 16 {
            HStack(spacing: 3) {
                ForEach(0..<renderedFrames.count, id: \.self) { _ in
                    Rectangle().fill(CanonColor.brass).frame(width: 3, height: 11)
                }
                ForEach(0..<generatingFrames.count, id: \.self) { _ in
                    Rectangle().fill(CanonColor.softGold.opacity(0.8)).frame(width: 3, height: 11)
                }
                ForEach(0..<plannedFrames.count, id: \.self) { _ in
                    Rectangle().stroke(CanonColor.hairlineDark, lineWidth: 1).frame(width: 3, height: 11)
                }
            }
        }
    }

    // MARK: Plates

    /// THE GILDED PLATE: the focused planned frame as cream plate stock —
    /// the one warm object in the dark room. Dashed brass keeps the
    /// planned-dash law; corner ticks are the plate's registration marks.
    private func plannedPlate(_ frame: ProjectLensHeroImage) -> some View {
        let failed = frame.status == "failed" || frame.status == "cancelled"
        let tint = failed ? CanonColor.rust : CanonColor.brass
        let titles = plannedTitle(frame)
        return VStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint.opacity(0.85))
                PlateLabel(
                    text: plateEyebrow(frame, failed: failed),
                    size: 8,
                    color: failed ? CanonColor.rust : PlateColor.inkFaint
                )
            }
            Text(titles.title)
                .font(CanonType.display(20, weight: .semibold))
                .foregroundStyle(PlateColor.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 18)
            if !titles.sub.isEmpty {
                Text(titles.sub.uppercased())
                    .font(CanonType.archive(8, weight: .medium))
                    .kerning(3)
                    .foregroundStyle(PlateColor.inkFaint)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                ForEach(accentSwatches, id: \.id) { swatch in
                    Circle()
                        .fill(canonColor(fromHex: swatch.hex, fallback: PlateColor.inkFaint))
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(PlateColor.hairline, lineWidth: 0.5))
                        .help(swatch.name.trimmed.nilIfEmpty ?? swatch.hex)
                }
                if let style = frame.styleAuthorities.first?.title.trimmed.nilIfEmpty {
                    Text("Style · \(style)")
                        .font(CanonType.archive(7.5, weight: .medium))
                        .foregroundStyle(PlateColor.inkFaint)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
        }
        .frame(width: 300, height: 190)
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
    }

    /// The first-scene state leads with proof: the first rendered frame.
    @ViewBuilder
    private var renderedPlate: some View {
        if let frame = renderedFrames.first,
           let image = StripThumbnailCache.shared.image(path: frame.imagePath, maxPixel: 640) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 300, height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(CanonColor.hairlineDark, lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if let frame = renderedFrames.first { onOpenFrame(frame) }
                }
                .help("Your first rendered Frame — click to open it")
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(CanonColor.mediaCard)
                .frame(width: 300, height: 190)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(CanonColor.muted.opacity(0.6))
                )
        }
    }

    // MARK: Right panes

    private func artDirectPane(_ frame: ProjectLensHeroImage) -> some View {
        let prompt = frame.sourcePrompt.trimmed.nilIfEmpty ?? frame.prompt.trimmed
        return VStack(alignment: .leading, spacing: 10) {
            if !prompt.isEmpty {
                Text("THE BRIEF")
                    .font(CanonType.archive(6.5, weight: .semibold))
                    .kerning(1.8)
                    .foregroundStyle(CanonColor.muted)
                Text(prompt)
                    .font(CanonType.displayItalic(12.5))
                    .foregroundStyle(CanonColor.bone.opacity(0.75))
                    .lineSpacing(3)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    StageBrassPill(
                        title: frame.status == "failed" || frame.status == "cancelled" ? "RETRY RENDER" : "RENDER THIS FRAME",
                        icon: "sparkles",
                        disabledReason: renderBlockReason
                    ) {
                        onRender(frame)
                    }
                    .help(renderBlockReason.isEmpty
                        ? "One paid render with the plan's defaults — the brief, the plan's style, and each character's reference sheet."
                        : renderBlockReason)
                    Text(renderCaption.uppercased())
                        .font(CanonType.archive(7.5, weight: .medium))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }
                Button {
                    onArtDirect(frame)
                } label: {
                    Text("ART-DIRECT →")
                        .font(CanonType.archive(8, weight: .bold))
                        .kerning(1.0)
                        .foregroundStyle(CanonColor.brass)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("Open the Frame Creator — shape the prompt and style, then render it in place.")
                if plannedFrames.count > 1 {
                    planStepper(current: frame)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var startFirstScenePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A Scene holds Frames and Footage in order — Scenes render to video and line up into the final sequence.")
                .font(CanonType.displayItalic(12.5))
                .foregroundStyle(CanonColor.bone.opacity(0.75))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            StageBrassPill(title: "START YOUR FIRST SCENE", icon: "film.stack") {
                onStartFirstScene()
            }
            .help("Creates a Scene with your first rendered Frame already placed — you can also right-click any rendered Frame below, or press + NEW in the rail")
            if !plannedFrames.isEmpty {
                Text("\(plannedFrames.count) suggested Frame\(plannedFrames.count == 1 ? " remains" : "s remain") — click one in the strip to render it.")
                    .font(CanonType.archive(7.5, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planStepper(current: ProjectLensHeroImage) -> some View {
        let index = plannedFrames.firstIndex { $0.imageId == current.imageId } ?? 0
        return HStack(spacing: 8) {
            stepperButton(systemName: "chevron.left") {
                let previous = (index - 1 + plannedFrames.count) % plannedFrames.count
                focusedImageId = plannedFrames[previous].imageId
            }
            Text("\(index + 1) OF \(plannedFrames.count) SUGGESTED")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(CanonColor.muted)
            stepperButton(systemName: "chevron.right") {
                let next = (index + 1) % plannedFrames.count
                focusedImageId = plannedFrames[next].imageId
            }
        }
    }

    private func stepperButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CanonColor.bone.opacity(0.85))
                .frame(width: 22, height: 22)
                .background(Circle().fill(CanonColor.mediaCardHover))
                .overlay(Circle().stroke(CanonColor.hairlineDark, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Filmstrip

    private enum StripKind {
        case rendered
        case generating
        case planned
    }

    private var stripEntries: [(frame: ProjectLensHeroImage, kind: StripKind)] {
        renderedFrames.map { ($0, StripKind.rendered) }
            + generatingFrames.map { ($0, StripKind.generating) }
            + plannedFrames.map { ($0, StripKind.planned) }
    }

    /// Every member of the plan as a numbered mini with its beat word.
    /// Rendered thumbs open, in-flight spin honestly, planned dashes focus
    /// (or art-direct once the first Scene is the primary move). Nothing here
    /// is draggable — placeable material lives in the pool.
    @ViewBuilder
    private var filmstrip: some View {
        if totalPlanCount > 1 {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(stripEntries.enumerated()), id: \.element.frame.imageId) { index, entry in
                    VStack(spacing: 4) {
                        miniCard(entry.frame, kind: entry.kind, ordinal: index + 1)
                        Text(miniLabel(entry.frame, kind: entry.kind))
                            .font(CanonType.archive(7, weight: .medium))
                            .foregroundStyle(CanonColor.muted)
                            .lineLimit(1)
                            .frame(width: 88)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func miniCard(_ frame: ProjectLensHeroImage, kind: StripKind, ordinal: Int) -> some View {
        switch kind {
        case .rendered:
            Button {
                onOpenFrame(frame)
            } label: {
                Group {
                    if let image = StripThumbnailCache.shared.image(path: frame.imagePath, maxPixel: 200) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        CanonColor.mediaCard
                    }
                }
                .frame(width: 88, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(CanonColor.hairlineDark, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(frame.label.trimmed.nilIfEmpty ?? "Rendered Frame") — click to open")
        case .generating:
            RoundedRectangle(cornerRadius: 6)
                .fill(CanonColor.mediaCard)
                .frame(width: 88, height: 50)
                .overlay(
                    ProgressView()
                        .controlSize(.mini)
                        .tint(CanonColor.softGold)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(CanonColor.hairlineDark, lineWidth: 1)
                )
                .help("\(frame.label.trimmed.nilIfEmpty ?? "Frame") — rendering now")
        case .planned:
            let isFocused = !isStartFirstScene && focusedPlan?.imageId == frame.imageId
            Button {
                if isStartFirstScene {
                    onArtDirect(frame)
                } else {
                    focusedImageId = frame.imageId
                }
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isFocused ? PlateColor.cream : Color.clear)
                    .frame(width: 88, height: 50)
                    .overlay(
                        Text(FrameCreatorModal.romanNumeral(ordinal).lowercased())
                            .font(PlateType.figure(13, weight: isFocused ? .semibold : .regular))
                            .foregroundStyle(isFocused ? PlateColor.ink : CanonColor.muted)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                isFocused ? CanonColor.brass : CanonColor.hairlineDark,
                                style: isFocused
                                    ? StrokeStyle(lineWidth: 1.5)
                                    : StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isStartFirstScene
                ? "\(frame.label.trimmed.nilIfEmpty ?? "Planned Frame") — click to art-direct and render it"
                : "\(frame.label.trimmed.nilIfEmpty ?? "Planned Frame") — click to focus it")
        }
    }

    private func miniLabel(_ frame: ProjectLensHeroImage, kind: StripKind) -> String {
        if kind == .generating { return "rendering" }
        let titles = plannedTitle(frame)
        let word = titles.sub.trimmed.nilIfEmpty ?? titles.title
        return word.lowercased()
    }

    // MARK: Derivations

    private func taxonomyNoun(_ frame: ProjectLensHeroImage) -> String {
        switch LensImageTaxonomyKind.normalized(frame.imageKind) {
        case LensImageTaxonomyKind.sceneImage: return "Scenery"
        case LensImageTaxonomyKind.characterImage: return "Character Study"
        case LensImageTaxonomyKind.objectImage: return "Object Study"
        case LensImageTaxonomyKind.areaImage: return "Setting"
        default: return "Frame"
        }
    }

    /// The v1 card's label split (" · " separates title from the beat), with
    /// one adjustment: "Character · Mara Vey" surfaces the NAME as the title.
    private func plannedTitle(_ frame: ProjectLensHeroImage) -> (title: String, sub: String) {
        let titles = scenesV2SuggestionTitle(label: frame.label)
        return (titles.title, titles.beat)
    }

    /// "Planned · Scenery", or "For Maelith · Scenery" when a sheet minted the row.
    private func plateEyebrow(_ frame: ProjectLensHeroImage, failed: Bool) -> String {
        let name = characterNamesById[frame.suggestedForCharacterId ?? ""] ?? ""
        let lead = name.isEmpty ? "Planned" : "For \(name)"
        let noun = frame.isSheetSuggestion ? "Moment" : taxonomyNoun(frame)
        return failed ? "\(lead) · Failed" : "\(lead) · \(noun)"
    }
}

/// Registration-mark corner ticks for the gilded plate — four brass L-marks
/// inset from the plate corners, the engraved-plate idiom in miniature.
struct PlateCornerTicks: Shape {
    var inset: CGFloat = 7
    var length: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX + inset
        let maxX = rect.maxX - inset
        let minY = rect.minY + inset
        let maxY = rect.maxY - inset
        path.move(to: CGPoint(x: minX, y: minY + length))
        path.addLine(to: CGPoint(x: minX, y: minY))
        path.addLine(to: CGPoint(x: minX + length, y: minY))
        path.move(to: CGPoint(x: maxX - length, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY))
        path.addLine(to: CGPoint(x: maxX, y: minY + length))
        path.move(to: CGPoint(x: maxX, y: maxY - length))
        path.addLine(to: CGPoint(x: maxX, y: maxY))
        path.addLine(to: CGPoint(x: maxX - length, y: maxY))
        path.move(to: CGPoint(x: minX + length, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: maxY))
        path.addLine(to: CGPoint(x: minX, y: maxY - length))
        return path
    }
}

/// The guided stage's one filled element: brass capsule, ink text, softGold
/// on hover (the CanonPrimaryButtonStyle family). Disabled keeps the ghost
/// outline so a refusal never masquerades as the action.
struct StageBrassPill: View {
    /// `filled` is the page's one brass element; `ghost` is the same capsule kept
    /// outline-only for a secondary action that must not compete with it.
    enum Style {
        case filled
        case ghost
    }

    /// `regular` is the stage's pill; `compact` is the same capsule at card scale.
    enum Size {
        case regular
        case compact
    }

    let title: String
    var icon: String = "arrow.up.right"
    var disabledReason: String = ""
    var style: Style = .filled
    var size: Size = .regular
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let enabled = disabledReason.isEmpty
        let ghost = style == .ghost
        let compact = size == .compact
        Button(action: action) {
            HStack(spacing: compact ? 5 : 7) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 9 : 10.5, weight: .bold))
                Text(title)
                    .font(CanonType.archive(compact ? 9 : 11, weight: .bold))
                    .kerning(compact ? 1.2 : 1.6)
            }
            .foregroundStyle(enabled ? (ghost ? CanonColor.brass : CanonColor.ink) : CanonColor.brass.opacity(0.5))
            .padding(.horizontal, compact ? 14 : 22)
            .frame(height: compact ? 28 : 36)
            .background(
                Capsule().fill(
                    enabled
                        ? (ghost
                            ? CanonColor.brass.opacity(isHovering ? 0.16 : 0.06)
                            : (isHovering ? CanonColor.softGold : CanonColor.brass))
                        : CanonColor.brass.opacity(0.06)
                )
            )
            .overlay(
                Capsule().stroke(
                    enabled ? (ghost ? CanonColor.brass.opacity(0.45) : Color.clear) : CanonColor.brass.opacity(0.25),
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { isHovering = $0 }
        .help(disabledReason)
    }
}
