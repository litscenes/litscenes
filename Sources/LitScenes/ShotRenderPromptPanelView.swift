import SwiftUI
import AppKit

/// The Re-render panel embedded in the shot player: every segment the render
/// would produce, its keyframe pair, and the exact prompt it would send —
/// editable per segment. Edits persist on the shot (keyed by frame image ids)
/// and seed the next visit; RESET returns a segment to the generated prompt.
/// Clicking a segment's keyframes plays that segment's saved clip in the
/// player. An untouched panel renders exactly what a one-click re-render
/// used to.
struct ShotRenderPromptPanel: View {
    let shot: ProjectShot
    let planSegments: [ShotRenderPlanSegment]
    let skipped: [String]
    /// Deliberately skipped segments, kept visible and restorable in place.
    let skippedPlaceholders: [ShotSkippedSegmentPlaceholder]
    /// True while another shot is rendering — one render at a time.
    let isRenderBlocked: Bool
    /// The segment key currently previewing in the player, for row highlight.
    let previewingSegmentKey: String?
    let configuredRenderModels: Set<ShotRenderModel>
    var onRender: ([ShotSegmentPromptOverride]) -> Void
    /// Render just one segment (by its "start>end" key), reusing the other
    /// segments' saved clips; passes all edited drafts like a full render.
    var onRenderSegment: ([ShotSegmentPromptOverride], String) -> Void
    /// Play a segment's saved clip in the player.
    var onPreviewSegment: (ShotRenderSegmentClip) -> Void
    var onSetDefaultRenderStack: (ShotRenderStack) -> Void
    var onSetSegmentRenderStack: (ShotRenderPair, ShotRenderStack?) -> Void
    /// Seam toggle on a footage row: (right entry's id, new style).
    var onSetSeamStyle: (String, ShotSeamStyle) -> Void = { _, _ in }
    /// Skip/restore an entry (footage or AI extension).
    var onSetEntrySkipped: (String, Bool) -> Void = { _, _ in }
    /// Seam-placeholder restore — separate from the explicit toggle so it
    /// never deletes a combined-cut boundary (THE SEAM BOUNDARY LAW).
    var onRestoreSkippedSeam: (String) -> Void = { _ in }
    /// Live FAL rates for the estimates; nil = rates unavailable (rendering
    /// still works, the figures just stay absent).
    var falPricing: FALPricingSnapshot? = nil
    var isFetchingRates: Bool = false
    /// Debounced draft autosave (upsert-only union — see
    /// mergedAutosavePromptOverrides); deletion stays a render/RESET behavior.
    var onAutosaveOverrides: ([ShotSegmentPromptOverride]) -> Void = { _ in }
    /// Copy this segment CARD (pair + edited prompt + stack + rendered take)
    /// to the picture clipboard — paste lands it in another CUT as
    /// first-class material. Passes the card's CURRENT draft text.
    var onCopySegmentCard: (ShotSegmentPromptPlanItem, String) -> Void = { _, _ in }
    /// Persists segment direction plans (beats). Autosave passes the
    /// upsert-only merge; confirm passes the wholesale computed set — the
    /// same two-lane law as prompt overrides.
    var onSaveDirectionPlans: ([ShotSegmentDirectionPlanRecord]) -> Void = { _ in }
    /// LLM beat-drafting lane state (keys are "shotId|pairKey") + triggers.
    var draftingDirectionKeys: Set<String> = []
    var directionDraftErrors: [String: String] = [:]
    var onDraftDirectionPlan: (String) -> Void = { _ in }
    var onDraftAllDirectionPlans: () -> Void = {}

    @State private var drafts: [String: String] = [:]
    @State private var planDrafts: [String: ShotTemporalDirectionPlan] = [:]
    @State private var modeDrafts: [String: ShotSegmentPromptMode] = [:]
    @State private var autosaveTask: Task<Void, Never>?
    /// The two-step spend law, matching the render-plan strip: the first
    /// click arms a button with its estimate, only the second click renders.
    /// Keyed per button ("full" or a segment key) so arming one disarms the
    /// others; any plan change disarms everything.
    @State private var armedRenderKey: String? = nil
    /// Bumped when a Hailuo resolution is picked — the preference lives in
    /// UserDefaults (not observed state), so the menu label needs a nudge.
    @State private var hailuoResolutionTick = 0

    /// The editable (generated) segments — footage rows carry no prompt.
    private var planItems: [ShotSegmentPromptPlanItem] {
        planSegments.compactMap { segment in
            if case .generated(let item) = segment { return item }
            return nil
        }
    }

    /// Honest runtime estimate: generated segments at the stack length plus
    /// the placed footage's real durations, minus the cut layer.
    private var estimatedSeconds: Int {
        let footageSeconds = planSegments.reduce(0.0) { total, segment in
            if case .footage(let footageSegment) = segment {
                return total + footageSegment.clip.resolvedDurationSeconds
            }
            return total
        }
        var total = planItems.reduce(footageSeconds) { partial, item in
            partial + Double(item.renderStack.segmentSeconds)
        }
        total -= shot.cutList.razorSecondsTotal
        total += shot.cutList.segmentCuts.reduce(0) { partial, cut in
            guard cut.joinRepair.mode == .generatedBridge,
                  let artifact = shot.joinBridgeVersion(cut.joinRepair.activeBridgeVersionId),
                  artifact.isReady else { return partial }
            return partial + artifact.durationSeconds
        }
        if let outSeconds = shot.cutList.shotOutSeconds {
            total = min(total, outSeconds)
        }
        if let inSeconds = shot.cutList.shotInSeconds {
            total -= inSeconds
        }
        return Int(max(total, 0).rounded())
    }

    /// Live segments interleaved with the skipped placeholders at their
    /// strip positions.
    private enum PanelRow: Identifiable {
        case segment(ShotRenderPlanSegment)
        case skippedSegment(ShotSkippedSegmentPlaceholder)

        var id: String {
            switch self {
            case .segment(let segment): return segment.id
            case .skippedSegment(let placeholder): return placeholder.id
            }
        }
    }

    private var panelRows: [PanelRow] {
        var rows: [PanelRow] = []
        for placeholder in skippedPlaceholders where placeholder.afterDisplayIndex < 0 {
            rows.append(.skippedSegment(placeholder))
        }
        for segment in planSegments {
            rows.append(.segment(segment))
            let displayIndex: Int
            switch segment {
            case .generated(let item): displayIndex = item.displayIndex
            case .footage(let footageSegment): displayIndex = footageSegment.displayIndex
            // Never in planSegments (assembly-only fallback band).
            case .artifactFallback: displayIndex = 0
            }
            for placeholder in skippedPlaceholders where placeholder.afterDisplayIndex == displayIndex {
                rows.append(.skippedSegment(placeholder))
            }
        }
        return rows
    }

    @ViewBuilder
    var body: some View {
        // The header (with the shot-level Model menu) renders ALWAYS — the
        // narration-driven state must never remove its own escape hatch.
        // Only the segment cards + footer swap for the whole-shot notice.
        VStack(spacing: 0) {
            panelHeader
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            if shot.renderStack.isNarrationDriven {
                narrationDrivenNotice
            } else {
                segmentList
                Rectangle().fill(PlateColor.hairline).frame(height: 1)
                footer
            }
        }
        .onChange(of: planItems.map(\.id)) { _, _ in
            armedRenderKey = nil
        }
        // Crash-safe drafts, same law as the inline plan strip: debounced,
        // upsert-only, flushed when the panel closes. Inert while the
        // narration notice shows (no editors, drafts never change).
        .onChange(of: drafts) { scheduleAutosave() }
        .onChange(of: planDrafts) { scheduleAutosave() }
        .onChange(of: modeDrafts) { scheduleAutosave() }
        .onDisappear {
            autosaveTask?.cancel()
            autosaveDrafts()
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            autosaveDrafts()
        }
    }

    private var narrationDrivenNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LTX 2.3 · NARRATION VIDEO")
                .font(CanonType.archive(8, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(CanonColor.brass)
            Text("This model renders one shot-wide clip from the active narration and the ANCHOR frame. Use RENDER on the cut rail to pick the anchor, review the 2–20 second driver, edit the visual prompt, and confirm the paid request — or switch the Model above to render keyframe segments again.")
                .font(CanonType.interface(11))
                .foregroundStyle(CanonColor.ink.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    private func autosaveDrafts() {
        let merged = mergedAutosavePromptOverrides(
            existing: shot.segmentPromptOverrides,
            computed: computedOverrides()
        )
        if !promptOverridesAgree(merged, shot.segmentPromptOverrides) {
            onAutosaveOverrides(merged)
        }
        let mergedPlans = mergedAutosaveDirectionPlans(
            existing: shot.segmentDirectionPlans,
            computed: computedPlans()
        )
        if !directionPlansAgree(mergedPlans, shot.segmentDirectionPlans) {
            onSaveDirectionPlans(mergedPlans)
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            PlateLabel(text: "Segment Prompts", size: 9.5, weight: .semibold)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            if !shot.renderStack.isNarrationDriven, planItems.count > 1 {
                Button("Draft all beats (\(planItems.count))") {
                    onDraftAllDirectionPlans()
                }
                .buttonStyle(PlateButtonStyle())
                .disabled(!draftingDirectionKeys.isEmpty)
                .help("Have the LLM draft beats for every segment, one at a time — fresh drafts are skipped; nothing renders")
            }
            defaultRenderControls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var segmentList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(panelRows) { row in
                    switch row {
                    case .segment(.generated(let item)):
                        segmentRow(item)
                    case .segment(.footage(let footageSegment)):
                        footageRow(footageSegment)
                    case .segment(.artifactFallback):
                        // Never in planSegments (assembly-only fallback band).
                        EmptyView()
                    case .skippedSegment(let placeholder):
                        skippedSegmentRow(placeholder)
                    }
                }
                if !skipped.isEmpty {
                    PlateLabel(
                        text: "Skipped \(skipped.count) not-ready frame\(skipped.count == 1 ? "" : "s")",
                        size: 8.5,
                        color: PlateColor.inkFaint
                    )
                }
            }
            .padding(14)
        }
        .frame(maxHeight: .infinity)
    }

    /// A deliberately skipped segment, held in place: out of the stitch,
    /// seams healed to hard cuts, one click from coming back.
    private func skippedSegmentRow(_ placeholder: ShotSkippedSegmentPlaceholder) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PlateColor.inkFaint)
            VStack(alignment: .leading, spacing: 3) {
                PlateLabel(
                    text: "\(placeholder.label) · skipped",
                    size: 9,
                    weight: .semibold,
                    color: PlateColor.inkFaint
                )
                Text("Out of the stitch — its seams healed to ‖ hard cuts.")
                    .font(PlateType.label(10, weight: .regular))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            Spacer(minLength: 0)
            Button("Restore") {
                switch placeholder.restore {
                case .entry(let entryId):
                    onSetEntrySkipped(entryId, false)
                case .seam(let rightEntryId):
                    onRestoreSkippedSeam(rightEntryId)
                }
            }
            .buttonStyle(PlateButtonStyle())
            .help("Put it back in the shot — free; reuses its saved clip when one exists")
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(PlateColor.creamDeep.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(PlateColor.inkFaint, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    /// The razor ranges currently biting this segment's material.
    private func razorNote(forKey segmentKey: String, isFootage: Bool) -> String? {
        let cuts = shot.cutList.segmentCuts.filter { $0.segmentKey == segmentKey }
        guard !cuts.isEmpty else { return nil }
        let ranges = cuts
            .map { String(format: "%.1f–%.1fs", $0.startSeconds, $0.endSeconds) }
            .joined(separator: ", ")
        return isFootage
            ? "Razor \(ranges) — persists across renders"
            : "Razor \(ranges) — pinned to this take; a re-render clears it"
    }

    /// The active version's clip behind this segment — the provenance the
    /// AS RENDERED delta compares against the next-render stack.
    private func activeClip(_ item: ShotSegmentPromptPlanItem) -> ShotRenderSegmentClip? {
        shot.activeRenderVersion?.segmentClip(
            placementStartEntryId: item.pair.startPlacementEntryId,
            placementEndEntryId: item.pair.endPlacementEntryId,
            forStart: item.pair.start?.imageId ?? "",
            end: item.pair.end?.imageId ?? ""
        )
    }

    private func segmentRow(_ item: ShotSegmentPromptPlanItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            keyframePair(item)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PlateLabel(
                        text: "Segment \(item.displayIndex + 1) of \(planSegments.count) · ~\(item.renderStack.segmentSeconds)s",
                        size: 8.5,
                        weight: .semibold,
                        color: PlateColor.inkFaint
                    )
                    if beatsAwareEdited(item) {
                        PlateLabel(text: "Edited", size: 8, weight: .semibold, color: PlateColor.ink)
                    }
                    Spacer(minLength: 0)
                    if item.pair.start != nil, item.pair.end != nil {
                        Button("Copy") {
                            onCopySegmentCard(item, cardText(for: item))
                        }
                        .buttonStyle(PlateButtonStyle())
                        .help("Copy this segment — keyframes, prompt, stack, and its rendered take — to the picture clipboard. Paste it onto another CUT row (right-click the row) or in that CUT's player: it plays there at $0 and can re-render there later")
                    }
                    // Beats mode owns its own reset menu inside the editor.
                    if modeValue(for: item) == .raw, isEdited(item) {
                        Button("Reset") {
                            drafts[item.pairKey] = item.generatedPrompt
                        }
                        .buttonStyle(PlateButtonStyle())
                        .help("Return this segment to the generated prompt")
                    }
                    if let skipTarget = item.skipTarget, planSegments.count > 1 {
                        Button("Skip") {
                            switch skipTarget {
                            case .entry(let entryId):
                                onSetEntrySkipped(entryId, true)
                            case .seam(let rightEntryId):
                                onSetSeamStyle(rightEntryId, .cut)
                            }
                        }
                        .buttonStyle(PlateButtonStyle())
                        .help("Skip this segment — out of the stitch, its seams heal to a hard cut. Free, and always restorable")
                    }
                    if planSegments.count > 1 {
                        let segmentKey = item.pair.placementKey
                        let isArmed = armedRenderKey == segmentKey
                        // THE HONEST BILL: "$0 reuse" is only true for other
                        // segments that HAVE a saved clip on the active
                        // version. Others without one (e.g. after a whole-
                        // shot LTX version, whose single clip matches no
                        // pair) are regenerated and billed too — price and
                        // promise must say so, never assume reuse.
                        let missingOthers = planItems.filter {
                            $0.pair.placementKey != segmentKey && activeClip($0) == nil
                        }
                        let billedItems = [item] + missingOthers
                        let billedUSDs = billedItems.compactMap {
                            ShotRenderCostEstimate.segmentUSD(item: $0, pricing: falPricing)
                        }
                        let billedUSD: Double? = billedUSDs.count == billedItems.count
                            ? billedUSDs.reduce(0, +)
                            : nil
                        let extraSuffix = missingOthers.isEmpty
                            ? ""
                            : " +\(missingOthers.count) unsaved"
                        let reuseTail = missingOthers.isEmpty
                            ? "the other segments' saved clips traveling in at $0"
                            : "\(missingOthers.count) other segment\(missingOthers.count == 1 ? " has" : "s have") no saved clip on the active version, so this render regenerates and bills \(missingOthers.count == 1 ? "it" : "them") too"
                        let nextRoman = FrameCreatorModal.romanNumeral(
                            (shot.renderVersions.map(\.versionNumber).max() ?? 0) + 1
                        )
                        Button(isArmed
                            ? "Confirm\(extraSuffix)\(billedUSD.map { " · \(usdLabel($0))" } ?? "")"
                            : "Render segment\(extraSuffix)\(billedUSD.map { " · \(usdLabel($0))" } ?? "")") {
                            if isArmed {
                                armedRenderKey = nil
                                saveDirectionPlansForConfirm()
                                onRenderSegment(computedOverrides(), segmentKey)
                            } else {
                                armedRenderKey = segmentKey
                            }
                        }
                        .buttonStyle(PlateButtonStyle(isProminent: isArmed))
                        .disabled(isRenderBlocked
                            || !modelConfigured(item.renderStack.model)
                            || !leadInRenderable(item)
                            || !nativeExtendRenderable(item))
                        .help(isRenderBlocked
                            ? "A shot is already rendering"
                            : (!nativeExtendRenderable(item)
                                ? "Native Extend needs this AI extension directly after at least 73 frames of footage — choose an image-to-video model"
                                : (!leadInRenderable(item)
                                ? "\(item.renderStack.model.label) can't render an AI lead-in — it needs a model that accepts a tail frame alone"
                                : (!modelConfigured(item.renderStack.model)
                                    ? "Add the required API key in App Settings before rendering this segment"
                                    : (isArmed
                                        ? "Click again to render this segment with \(item.renderStack.shortLabel) — this spends, and the result lands as version \(nextRoman) with \(reuseTail)"
                                        : "Arms a confirm — nothing renders until the second click. Renders this segment with \(item.renderStack.shortLabel); the result lands as version \(nextRoman) with \(reuseTail)")))))
                    }
                }
                // THE HONEST DELTA: what this segment's current clip was
                // rendered with, shown ONLY when the next render would change
                // its recipe. This is the line that separates provenance from
                // intent at the exact moment they diverge.
                if let clip = activeClip(item),
                   let asRendered = shotSegmentAsRenderedDescriptor(clip: clip, nextStack: item.renderStack) {
                    PlateLabel(
                        text: "As rendered · \(asRendered) — next render · \(item.renderStack.shortLabel)",
                        size: 8,
                        weight: .semibold,
                        color: CanonColor.brass
                    )
                    .help("The current version's clip for this segment used a different recipe than the next render will. Rendering replaces this segment; the other segments' clips travel in verbatim.")
                }
                if let caption = bridgeCaption(item) {
                    PlateLabel(text: caption, size: 8, color: PlateColor.inkFaint)
                }
                if let note = razorNote(forKey: item.pair.placementKey, isFootage: false) {
                    PlateLabel(text: note, size: 8, color: PlateColor.inkFaint)
                }
                segmentRenderControls(item)
                ShotSegmentBeatsEditor(
                    item: item,
                    plan: planBinding(for: item),
                    mode: modeBinding(for: item),
                    isDrafting: draftingDirectionKeys.contains("\(shot.shotId)|\(item.pairKey)"),
                    draftError: directionDraftErrors["\(shot.shotId)|\(item.pairKey)"],
                    onDraft: { onDraftDirectionPlan(item.pairKey) }
                ) {
                    TextEditor(text: draftBinding(for: item))
                        .font(PlateType.label(11.5, weight: .regular))
                        .foregroundStyle(PlateColor.ink)
                        .scrollContentBackground(.hidden)
                        .frame(height: 110)
                        .padding(7)
                        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.55)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isEdited(item) ? PlateColor.ink.opacity(0.65) : PlateColor.hairline, lineWidth: 1)
                        )
                }
            }
        }
    }

    /// A footage segment: real material that plays verbatim — nothing to
    /// prompt. Clicking the thumb previews its saved clip when one exists.
    @ViewBuilder
    private func footageRow(_ footageSegment: ShotFootagePlanSegment) -> some View {
        let clip = footageSegment.clip
        let saved = shot.activeRenderVersion?.segmentClip(
            placementStartEntryId: clip.entryId,
            placementEndEntryId: "",
            forStart: clip.footageKey,
            end: ""
        ) ?? shot.seedSegmentClips.first { $0.placementKey == footageSegment.placementKey }
        let previewable = saved.flatMap { FileManager.default.fileExists(atPath: $0.clipPath) ? $0 : nil }
        let isPreviewing = previewingSegmentKey == previewable?.placementKey
        HStack(alignment: .top, spacing: 12) {
            Button {
                if let previewable {
                    onPreviewSegment(previewable)
                }
            } label: {
                ZStack {
                    PlateColor.creamDeep
                    if let image = (clip.videoStripPath.flatMap { NSImage(contentsOfFile: $0) })
                        ?? NSImage(contentsOfFile: clip.thumbnailPath) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "film.stack")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(PlateColor.inkFaint)
                    }
                }
                .frame(width: 120, height: 68)
                .clipped()
                .overlay(Rectangle().stroke(isPreviewing ? PlateColor.ink : PlateColor.hairline, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(previewable == nil)
            .help(previewable == nil
                ? "No saved clip for this footage yet — render to place it"
                : "Play this footage segment in the player")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    PlateLabel(
                        text: "Segment \(footageSegment.displayIndex + 1) of \(planSegments.count) · footage · \(String(format: "%.1f", clip.resolvedDurationSeconds))s",
                        size: 8.5,
                        weight: .semibold,
                        color: PlateColor.inkFaint
                    )
                    Spacer(minLength: 0)
                    Button("Skip") {
                        onSetEntrySkipped(clip.entryId, true)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help("Skip this footage — out of the stitch, its seams heal to hard cuts. Free, and always restorable")
                }
                PlateLabel(text: clip.filename, size: 9.5, weight: .semibold)
                footageSeamChips(footageSegment)
                if let note = razorNote(forKey: footageSegment.placementKey, isFootage: true) {
                    PlateLabel(text: note, size: 8, color: PlateColor.inkFaint)
                }
                Text("Real footage — plays verbatim, no prompt. Bridged neighbors hand off on its first and last frames.")
                    .font(PlateType.label(10.5, weight: .regular))
                    .foregroundStyle(PlateColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The bridge's honest introduction: which end stands on real footage.
    private func bridgeCaption(_ item: ShotSegmentPromptPlanItem) -> String? {
        let intoFootage = item.pair.end?.provider == "footage"
        if item.pair.start == nil {
            return intoFootage
                ? "Lead-in — arrives on the clip's real first frame"
                : "Lead-in — arrives on this frame"
        }
        let fromFootage = item.pair.start?.provider == "footage"
        switch (fromFootage, intoFootage) {
        case (true, true):
            return "Bridge between clips — real frames at both ends"
        case (true, false):
            return "Bridge from footage — starts on the clip's real last frame"
        case (false, true):
            return "Bridge into footage — arrives on the clip's real first frame"
        default:
            return nil
        }
    }

    /// The nearest non-skipped neighbor in the given direction, and whether
    /// a skipped entry sits between (the seam is then skip-healed to a cut —
    /// the placeholder row owns it, not a chip).
    private func survivingNeighbor(
        ofEntryAt index: Int,
        direction: Int
    ) -> (entry: ShotFrameEntry, skippedBetween: Bool)? {
        var skippedBetween = false
        var cursor = index + direction
        while cursor >= 0 && cursor < shot.entries.count {
            let candidate = shot.entries[cursor]
            if candidate.isSkipped {
                skippedBetween = true
                cursor += direction
                continue
            }
            return (candidate, skippedBetween)
        }
        return nil
    }

    /// The footage row's seam controls: how this clip JOINS its surviving
    /// neighbors. Toggling re-derives the plan live (bridge rows appear and
    /// disappear). Seams healed by a skip get no chip — restoring the skip
    /// is the way back.
    @ViewBuilder
    private func footageSeamChips(_ footageSegment: ShotFootagePlanSegment) -> some View {
        if let index = shot.entries.firstIndex(where: { $0.entryId == footageSegment.clip.entryId }) {
            let entry = shot.entries[index]
            HStack(spacing: 6) {
                if let (left, skippedBetween) = survivingNeighbor(ofEntryAt: index, direction: -1),
                   !left.isAIExtension, !skippedBetween {
                    let style = resolvedShotSeamStyle(
                        leftIsClip: left.isClip,
                        rightIsClip: entry.isClip,
                        rightPreference: entry.leadSeamPreference
                    )
                    Button("IN \(style == .cut ? "‖ CUT" : "≈ BRIDGED")") {
                        onSetSeamStyle(entry.entryId, style.toggled)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help(style == .cut
                        ? "Hard cut in — click to bridge (generated transition, one segment render)"
                        : "Generated bridge in — click to hard-cut (free)")
                }
                if let (right, skippedBetween) = survivingNeighbor(ofEntryAt: index, direction: 1),
                   !right.isAIExtension, !skippedBetween {
                    let style = resolvedShotSeamStyle(
                        leftIsClip: entry.isClip,
                        rightIsClip: right.isClip,
                        rightPreference: right.leadSeamPreference
                    )
                    Button("OUT \(style == .cut ? "‖ CUT" : "≈ BRIDGED")") {
                        onSetSeamStyle(right.entryId, style.toggled)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help(style == .cut
                        ? "Hard cut out — click to bridge (generated transition, one segment render)"
                        : "Generated bridge out — click to hard-cut (free)")
                }
            }
        }
    }

    @ViewBuilder
    private func keyframePair(_ item: ShotSegmentPromptPlanItem) -> some View {
        let clip = previewableSegmentClip(shot: shot, pair: item.pair) {
            FileManager.default.fileExists(atPath: $0)
        }
        let isPreviewing = previewingSegmentKey == item.pair.placementKey
        Button {
            if let clip {
                onPreviewSegment(clip)
            }
        } label: {
            VStack(spacing: 6) {
                if let start = item.pair.start {
                    keyframeThumbnail(start)
                    if let end = item.pair.end {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PlateColor.inkFaint)
                        keyframeThumbnail(end)
                    } else {
                        PlateLabel(text: "Open-ended", size: 7.5, color: PlateColor.inkFaint)
                    }
                } else if let end = item.pair.end {
                    PlateLabel(text: "Lead-in", size: 7.5, color: PlateColor.inkFaint)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PlateColor.inkFaint)
                    keyframeThumbnail(end)
                }
            }
            .padding(3)
            .overlay(Rectangle().stroke(isPreviewing ? PlateColor.ink : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(clip == nil)
        .help(clip == nil
            ? "No saved segment yet — render to save one"
            : (isPreviewing ? "This segment is playing" : "Play this segment in the player"))
    }

    private func keyframeThumbnail(_ frame: ProjectLensHeroImage) -> some View {
        ZStack {
            PlateColor.creamDeep
            // Plan pairs only carry ready frames with an image on disk.
            if let image = NSImage(contentsOfFile: frame.imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
        }
        .frame(width: 120, height: 68)
        .clipped()
        .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            let stacks = Set(planItems.map(\.renderStack))
            let recipeLabel = stacks.count > 1
                ? "MIXED RECIPES"
                : (stacks.first?.shortLabel ?? shot.renderStack.shortLabel)
            PlateLabel(
                text: "\(recipeLabel) · \(planSegments.count) segment\(planSegments.count == 1 ? "" : "s") · ~\(estimatedSeconds)s",
                size: 8.5,
                color: PlateColor.inkFaint
            )
            if isRenderBlocked {
                PlateLabel(text: "A shot is already rendering", size: 8.5, color: PlateColor.inkFaint)
            }
            Spacer()
            // Same vocabulary law as the rail and plan strip: a seed-covered
            // draft (combined, or pasted-into) bills only its uncovered
            // segments, and a fully seeded one FINALIZEs locally for $0.
            let renderCTA = cutRenderCTA(cut: shot, segmentCount: planSegments.count)
            let readableSeedKeys = renderCTA.isSeedDraft ? cutReadableSeedKeys(cut: shot) : []
            let billableItems = renderCTA.isSeedDraft
                ? planItems.filter { !readableSeedKeys.contains($0.pair.placementKey) }
                : planItems
            let estimate = ShotRenderCostEstimate.estimate(
                items: billableItems,
                pricing: falPricing,
                isFetchingRates: isFetchingRates
            )
            if estimate.headlineLabel == nil, !isFetchingRates, !billableItems.isEmpty {
                PlateLabel(text: "rates unavailable", size: 8, color: PlateColor.inkFaint)
                    .help("FAL rates could not be fetched — rendering still works; the estimate appears once rates load")
            }
            let isArmed = armedRenderKey == "full"
            let cta = renderCTAContent(renderCTA, isArmed: isArmed, estimate: estimate)
            Button(cta.title) {
                if isArmed {
                    armedRenderKey = nil
                    saveDirectionPlansForConfirm()
                    onRender(computedOverrides())
                } else {
                    armedRenderKey = "full"
                }
            }
            .buttonStyle(PlateButtonStyle(isProminent: true))
            .disabled(isRenderBlocked
                || planSegments.isEmpty
                || !allEffectiveModelsConfigured
                || !allLeadInsRenderable
                || !allNativeExtendsRenderable)
            .help(cta.help)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func renderCTAContent(
        _ renderCTA: CutRenderCTA,
        isArmed: Bool,
        estimate: ShotRenderCostEstimate
    ) -> (title: String, help: String) {
        switch renderCTA {
        case .finalizeFree:
            return (
                isArmed ? "Confirm · $0" : "Finalize · $0",
                isArmed
                    ? "Click again to assemble locally — no provider call, $0"
                    : "All source video is reusable — assemble a ready version locally for $0"
            )
        case .renderMissing:
            return (
                "\(isArmed ? "Confirm" : "Render missing")\(estimate.headlineLabel.map { " · \($0)" } ?? "")",
                isArmed
                    ? "Click again to render — this spends. Exactly these prompts run"
                    : "Only the seed-uncovered segments bill; reusable source clips travel verbatim"
            )
        case .render:
            return (
                isArmed
                    ? "Confirm\(estimate.headlineLabel.map { " · \($0)" } ?? " render")"
                    : "Render\(estimate.headlineLabel.map { " · \($0)" } ?? "")",
                isArmed ? "Click again to render — this spends. Exactly these prompts run" : renderHelp
            )
        }
    }

    /// Strip-matching money format: sub-cent rates keep a third decimal.
    private func usdLabel(_ value: Double) -> String {
        value < 0.01 && value > 0 ? String(format: "$%.3f", value) : String(format: "$%.2f", value)
    }

    private var defaultRenderControls: some View {
        HStack(spacing: 6) {
            PlateLabel(text: "Default", size: 7.5, color: PlateColor.inkFaint)
            PlateLabel(text: "Model", size: 7, color: PlateColor.inkFaint)
            modelMenu(
                stack: shot.renderStack,
                availableModels: ShotRenderModel.shotDefaultCases,
                onSelect: { onSetDefaultRenderStack(shot.renderStack.replacingModel($0)) }
            )
            PlateLabel(text: "Length", size: 7, color: PlateColor.inkFaint)
            durationMenu(
                stack: shot.renderStack,
                onSelect: { onSetDefaultRenderStack(shot.renderStack.replacingDuration($0)) }
            )
            if !Hailuo3ResolutionPreference.choices(for: shot.renderStack.model).isEmpty {
                PlateLabel(text: "Res", size: 7, color: PlateColor.inkFaint)
                hailuoResolutionMenu(model: shot.renderStack.model)
            }
            if shot.renderStack.model.supportsGeneratedAudio {
                PlateLabel(text: "Audio", size: 7, color: PlateColor.inkFaint)
                audioMenu(
                    stack: shot.renderStack,
                    onSelect: {
                        onSetDefaultRenderStack(
                            shot.renderStack.replacingGeneratedAudio($0)
                        )
                    }
                )
            }
        }
    }

    private func segmentRenderControls(_ item: ShotSegmentPromptPlanItem) -> some View {
        HStack(spacing: 7) {
            PlateLabel(
                text: item.hasRenderOverride ? "Override" : "Shot default",
                size: 7.5,
                weight: item.hasRenderOverride ? .semibold : .regular,
                color: item.hasRenderOverride ? PlateColor.ink : PlateColor.inkFaint
            )
            modelMenu(
                stack: item.renderStack,
                shape: segmentShape(item.pair),
                allowsNarrationDriven: false,
                availableModels: ShotRenderModel.shotDefaultCases
                    + (item.canUseNativeFootageExtend ? [.ltx23NativeExtend] : []),
                onSelect: { model in
                    setSegmentStack(item, stack: item.renderStack.replacingModel(model))
                }
            )
            durationMenu(
                stack: item.renderStack,
                onSelect: { seconds in
                    setSegmentStack(item, stack: item.renderStack.replacingDuration(seconds))
                }
            )
            if !Hailuo3ResolutionPreference.choices(for: item.renderStack.model).isEmpty {
                hailuoResolutionMenu(model: item.renderStack.model)
            }
            if item.renderStack.model.supportsGeneratedAudio
                && !item.renderStack.model.requiresGeneratedAudio {
                audioMenu(
                    stack: item.renderStack,
                    onSelect: { enabled in
                        setSegmentStack(
                            item,
                            stack: item.renderStack.replacingGeneratedAudio(enabled)
                        )
                    }
                )
            }
            if item.hasRenderOverride {
                Button("Use Defaults") {
                    onSetSegmentRenderStack(item.pair, nil)
                }
                .buttonStyle(.plain)
                .font(PlateType.label(9, weight: .regular))
                .foregroundStyle(PlateColor.inkFaint)
                .help("Remove this segment's model, length, and audio override")
            }
            Spacer(minLength: 0)
            if item.pair.start == nil, item.renderStack.tailAnchoredModelSelection == nil {
                PlateLabel(text: "No lead-in model", size: 7.5, color: CanonColor.rust)
                    .help("\(item.renderStack.model.label) can't render an end-anchored lead-in — it needs a model that accepts a tail frame alone")
            }
            if !modelConfigured(item.renderStack.model) {
                PlateLabel(text: "Needs API key", size: 7.5, color: CanonColor.rust)
            }
        }
    }

    /// Which anchor shape a segment renders with — drives the model menu's
    /// labels, availability, and help.
    private enum SegmentShape {
        case paired
        case openEnded
        case leadIn
    }

    private func segmentShape(_ pair: ShotRenderPair) -> SegmentShape {
        if pair.start == nil { return .leadIn }
        return pair.end == nil ? .openEnded : .paired
    }

    private func modelMenu(
        stack: ShotRenderStack,
        shape: SegmentShape = .paired,
        /// LTX 2.3 Narration renders ONE narration-driven clip for the whole
        /// shot — it is a SHOT DEFAULT, never a per-segment override (the
        /// segment loop has no narration driver to hand it; before this gate
        /// the pick failed mid-render with a scary provider error).
        allowsNarrationDriven: Bool = true,
        availableModels: [ShotRenderModel] = ShotRenderModel.shotDefaultCases,
        onSelect: @escaping (ShotRenderModel) -> Void
    ) -> some View {
        Menu {
            ForEach(availableModels) { model in
                let canLeadIn = shape != .leadIn
                    || stack.replacingModel(model).tailAnchoredModelSelection != nil
                let narrationBlocked = !allowsNarrationDriven
                    && stack.replacingModel(model).isNarrationDriven
                Button {
                    onSelect(model)
                } label: {
                    let label = modelLabel(model, shape: shape)
                    let availabilityLabel = narrationBlocked
                        ? "\(label) · whole-shot only (set as Shot default)"
                        : (modelConfigured(model) ? label : "\(label) · needs API key")
                    if model == stack.model {
                        Label(availabilityLabel, systemImage: "checkmark")
                    } else {
                        Text(availabilityLabel)
                    }
                }
                .disabled(!modelConfigured(model) || !canLeadIn || narrationBlocked)
            }
        } label: {
            settingLabel(modelLabel(stack.model, shape: shape))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help({
            switch shape {
            case .paired: return "Paired first/last-frame model used on the next render"
            case .openEnded: return "Open-ended model used on the next render"
            case .leadIn: return "Lead-in model used on the next render — needs one that accepts a tail frame alone"
            }
        }())
    }

    /// Standalone resolution menu (beside Length/Audio) for the Hailuo
    /// stacks — writes the global per-model preference, never the recipe.
    private func hailuoResolutionMenu(model: ShotRenderModel) -> some View {
        Menu {
            Hailuo3ResolutionMenuSection(
                model: model,
                showsDivider: false,
                onPicked: { hailuoResolutionTick += 1 }
            )
        } label: {
            settingLabel(Hailuo3ResolutionPreference.resolution(for: model))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .id(hailuoResolutionTick)
        .help("Hailuo render resolution — a global per-model preference read at render time. The cost estimate uses FAL's reported endpoint rate regardless of this choice.")
    }

    private func durationMenu(
        stack: ShotRenderStack,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        Menu {
            ForEach(stack.model.supportedDurations, id: \.self) { seconds in
                Button {
                    onSelect(seconds)
                } label: {
                    if seconds == stack.segmentSeconds {
                        Label("\(seconds)s", systemImage: "checkmark")
                    } else {
                        Text("\(seconds)s")
                    }
                }
            }
        } label: {
            settingLabel("\(stack.segmentSeconds)s")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Length of this generated segment on the next render")
    }

    private func audioMenu(
        stack: ShotRenderStack,
        onSelect: @escaping (Bool) -> Void
    ) -> some View {
        Menu {
            Button {
                onSelect(false)
            } label: {
                if !stack.generateAudio {
                    Label("Off", systemImage: "checkmark")
                } else {
                    Text("Off")
                }
            }
            Button {
                onSelect(true)
            } label: {
                if stack.generateAudio {
                    Label("On", systemImage: "checkmark")
                } else {
                    Text("On")
                }
            }
        } label: {
            settingLabel(stack.generateAudio ? "Audio on" : "Audio off")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Generate provider-native audio for this segment on the next render")
    }

    private func settingLabel(_ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(PlateType.label(9, weight: .semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 6, weight: .bold))
        }
        .foregroundStyle(PlateColor.ink)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline, lineWidth: 1))
    }

    private func setSegmentStack(_ item: ShotSegmentPromptPlanItem, stack: ShotRenderStack) {
        onSetSegmentRenderStack(item.pair, stack == shot.renderStack ? nil : stack)
    }

    /// A lead-in row renders only when its effective stack has a tail-anchored
    /// model — everything else is always renderable.
    private func leadInRenderable(_ item: ShotSegmentPromptPlanItem) -> Bool {
        item.pair.start != nil || item.renderStack.tailAnchoredModelSelection != nil
    }

    private var allLeadInsRenderable: Bool {
        planItems.allSatisfy(leadInRenderable)
    }

    private func nativeExtendRenderable(_ item: ShotSegmentPromptPlanItem) -> Bool {
        !item.renderStack.isNativeFootageExtend || item.canUseNativeFootageExtend
    }

    private var allNativeExtendsRenderable: Bool {
        planItems.allSatisfy(nativeExtendRenderable)
    }

    private func modelConfigured(_ model: ShotRenderModel) -> Bool {
        configuredRenderModels.contains(model)
    }

    private func modelLabel(_ model: ShotRenderModel, shape: SegmentShape) -> String {
        switch shape {
        case .paired:
            return model.label
        case .openEnded:
            return model == .klingV26Pro ? "Kling v2.6 Standard" : model.label
        case .leadIn:
            let canLeadIn = ShotRenderStack.fallback.replacingModel(model).tailAnchoredModelSelection != nil
            return canLeadIn ? model.label : "\(model.label) — no lead-in"
        }
    }

    private var allEffectiveModelsConfigured: Bool {
        planItems.allSatisfy { modelConfigured($0.renderStack.model) }
    }

    private var renderHelp: String {
        if isRenderBlocked { return "A video render is already running" }
        if !allLeadInsRenderable {
            return "The AI lead-in needs a model that accepts a tail frame alone"
        }
        if !allNativeExtendsRenderable {
            return "Native Extend needs an AI extension directly after at least 73 frames of footage — choose an image-to-video model"
        }
        if !allEffectiveModelsConfigured {
            return "Add the required FAL or Kling API key in App Settings before rendering"
        }
        return "Render the shot with these prompts, models, segment lengths, and audio choices"
    }

    // MARK: Drafts
    //
    // Lazy, pair-keyed drafts (same law as the inline render-plan strip): an
    // untouched box reads override-else-generated from the live plan, so the
    // in-panel Skip button re-pairing segments can never orphan a draft or
    // blank a row, and saving never wipes overrides this panel never showed.

    private func draftValue(for item: ShotSegmentPromptPlanItem) -> String {
        drafts[item.pairKey] ?? item.overridePrompt ?? item.generatedPrompt
    }

    private func draftBinding(for item: ShotSegmentPromptPlanItem) -> Binding<String> {
        Binding(
            get: { draftValue(for: item) },
            set: { drafts[item.pairKey] = $0 }
        )
    }

    private func isEdited(_ item: ShotSegmentPromptPlanItem) -> Bool {
        draftValue(for: item).trimmed != item.generatedPrompt.trimmed
    }

    /// "Edited" per mode: beats compares the plan draft against its pristine
    /// source (LLM draft, else the one-beat default); raw keeps the classic
    /// text comparison.
    private func beatsAwareEdited(_ item: ShotSegmentPromptPlanItem) -> Bool {
        guard modeValue(for: item) == .beats else { return isEdited(item) }
        let pristine = item.directionPlan?.llmDraftPlan?.normalized()
            ?? shotFallbackDirectionPlan(pair: item.pair).normalized()
        return planValue(for: item).normalized() != pristine
    }

    /// Delegates to the shared pure function so the panel and the inline
    /// render-plan strip persist overrides identically.
    private func computedOverrides() -> [ShotSegmentPromptOverride] {
        computedSegmentPromptOverrides(drafts: drafts, items: planItems, now: DateFormats.now())
    }

    // MARK: Beats drafts (same lazy pair-keyed law as the text drafts)

    private func planValue(for item: ShotSegmentPromptPlanItem) -> ShotTemporalDirectionPlan {
        planDrafts[item.pairKey]
            ?? item.directionPlan?.plan
            ?? shotFallbackDirectionPlan(pair: item.pair)
    }

    private func modeValue(for item: ShotSegmentPromptPlanItem) -> ShotSegmentPromptMode {
        modeDrafts[item.pairKey] ?? item.promptMode
    }

    private func planBinding(for item: ShotSegmentPromptPlanItem) -> Binding<ShotTemporalDirectionPlan> {
        Binding(
            get: { planValue(for: item) },
            set: { planDrafts[item.pairKey] = $0 }
        )
    }

    /// The eject law lives in the setter: leaving beats seeds the raw box
    /// with the compiled text, so nothing the user built silently vanishes;
    /// returning to beats restores the retained plan draft untouched.
    private func modeBinding(for item: ShotSegmentPromptPlanItem) -> Binding<ShotSegmentPromptMode> {
        Binding(
            get: { modeValue(for: item) },
            set: { newMode in
                if newMode == .raw, modeValue(for: item) == .beats,
                   let selection = item.renderStack.modelSelection(for: item.pair),
                   let compiled = compileTemporalDirection(
                       plan: planValue(for: item),
                       modelSelection: selection,
                       durationSeconds: item.renderStack.segmentSeconds
                   ) {
                    drafts[item.pairKey] = compiled.canonicalText
                }
                modeDrafts[item.pairKey] = newMode
            }
        )
    }

    /// The card/clipboard text for a segment: in beats mode the LIVE compiled
    /// canonical text, else the classic draft value.
    private func cardText(for item: ShotSegmentPromptPlanItem) -> String {
        if modeValue(for: item) == .beats,
           let selection = item.renderStack.modelSelection(for: item.pair),
           let compiled = compileTemporalDirection(
               plan: planValue(for: item),
               modelSelection: selection,
               durationSeconds: item.renderStack.segmentSeconds
           ) {
            return compiled.canonicalText
        }
        return draftValue(for: item)
    }

    /// Delegates to the shared pure sibling so both surfaces persist plans
    /// identically.
    private func computedPlans() -> [ShotSegmentDirectionPlanRecord] {
        computedSegmentDirectionPlans(
            planDrafts: planDrafts,
            modeDrafts: modeDrafts,
            items: planItems,
            existing: shot.segmentDirectionPlans,
            now: DateFormats.now()
        )
    }

    /// Confirm-time persist order: plans first, then overrides ride the
    /// existing callbacks — a crash between the two still leaves a coherent
    /// render (the compiled text is derivable from the plan).
    private func saveDirectionPlansForConfirm() {
        onSaveDirectionPlans(computedPlans())
    }
}

/// THE HAILUO RESOLUTION SECTION — the same checkmarked choices inside any
/// stack picker's Hailuo submenu (the NEXT chip) or standalone menu (the
/// render panel). Writes `Hailuo3ResolutionPreference` (global per model,
/// read at request-build time); renders nothing for non-Hailuo models.
struct Hailuo3ResolutionMenuSection: View {
    let model: ShotRenderModel
    var showsDivider: Bool = true
    var onPicked: () -> Void = {}

    /// The preference is UserDefaults, not observed — this keeps the
    /// checkmark honest while the menu stays open.
    @State private var refreshTick = 0

    var body: some View {
        let choices = Hailuo3ResolutionPreference.choices(for: model)
        if !choices.isEmpty {
            if showsDivider {
                Divider()
            }
            ForEach(choices, id: \.self) { choice in
                Button {
                    Hailuo3ResolutionPreference.setResolution(choice, for: model)
                    refreshTick += 1
                    onPicked()
                } label: {
                    if Hailuo3ResolutionPreference.resolution(for: model) == choice {
                        Label("Resolution \u{00B7} \(choice)", systemImage: "checkmark")
                    } else {
                        Text("Resolution \u{00B7} \(choice)")
                    }
                }
            }
            .id(refreshTick)
        }
    }
}
