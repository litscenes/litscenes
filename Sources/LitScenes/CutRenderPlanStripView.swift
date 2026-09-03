import SwiftUI
import AppKit

// MARK: - Render plan strip (the two-step RENDER disclosure)
//
// Clicking RENDER no longer spends money — it slides this strip open under
// the cut's rail (the NARRATE pattern): every generated segment with its
// start→end keyframes, effective model + duration, an editable prompt box
// (exactly what the provider will receive), a live FAL cost estimate, and a
// confirm button that saves prompt edits as overrides and fires the render.

struct CutRenderPlanStrip: View {
    let cut: ProjectShot
    var actions: CutStripActions
    /// Mirrors the owning strip's layout: `.box` prints the plan on the
    /// SCENES v2 cream plate; `.standard` keeps the row's original dress.
    var layout: CutStripLayout = .standard
    var focusedSegmentKey: String? = nil
    var onCancel: () -> Void = {}
    /// The filter is nil for a full render; a key set renders only those
    /// segments and reuses every other saved clip (suffix render / resume).
    var onConfirm: ([ShotSegmentPromptOverride], Set<String>?) -> Void = { _, _ in }

    // MARK: Dress
    //
    // Every `.standard` arm is the panel's original literal, so the SCENES
    // tab renders exactly as before; `.box` swaps in the plate stock.
    private var isPlate: Bool { layout == .box }
    private var panelFill: Color { isPlate ? ScenesV2StageDress.insetFill : CanonColor.paperInset.opacity(0.45) }
    private func hairline(_ legacyOpacity: Double? = nil) -> Color {
        if isPlate { return ScenesV2StageDress.hairline }
        if let legacyOpacity { return CanonColor.hairlinePaper.opacity(legacyOpacity) }
        return CanonColor.hairlinePaper
    }
    private var labelInk: Color { isPlate ? ScenesV2StageDress.inkFaint : CanonColor.muted }
    private func quiet(_ legacyOpacity: Double) -> Color {
        isPlate ? ScenesV2StageDress.inkFaint : CanonColor.muted.opacity(legacyOpacity)
    }
    private func bodyInk(_ legacyOpacity: Double) -> Color {
        isPlate ? ScenesV2StageDress.ink : CanonColor.ink.opacity(legacyOpacity)
    }
    private func chipFill(_ legacyOpacity: Double) -> Color {
        isPlate ? ScenesV2StageDress.cardFill : CanonColor.paperInset.opacity(legacyOpacity)
    }
    private var editorFill: Color { isPlate ? ScenesV2StageDress.cardFill : Color.white.opacity(0.55) }
    private var reusedEditorFill: Color { isPlate ? ScenesV2StageDress.cardFill.opacity(0.6) : Color.white.opacity(0.3) }
    private var narrationEditorFill: Color { isPlate ? ScenesV2StageDress.cardFill : CanonColor.paper.opacity(0.68) }
    private var ghostTint: Color { isPlate ? ScenesV2StageDress.inkFaint : CanonColor.muted }
    /// The one filled element: ink on brass on the plate, paper on brass in the row.
    private var confirmInk: Color { isPlate ? CanonColor.ink : CanonColor.paper }

    @State private var drafts: [String: String] = [:]
    @State private var planDrafts: [String: ShotTemporalDirectionPlan] = [:]
    @State private var modeDrafts: [String: ShotSegmentPromptMode] = [:]
    @State private var autosaveTask: Task<Void, Never>?
    /// Local face verdict for the narration anchor (nil while checking). The
    /// engine re-runs the same law at render time — this is the mirror that
    /// says it before the click.
    @State private var anchorFaceVerdict: ShotAnchorLipSyncVerdict?

    private var plan: (
        segments: [ShotRenderPlanSegment],
        generatedItems: [ShotSegmentPromptPlanItem],
        skipped: [String],
        strands: [MeaningStrand],
        skippedPlaceholders: [ShotSkippedSegmentPlaceholder]
    ) {
        shotRenderSegmentPlan(
            shot: cut,
            frameLookup: actions.frameLookup,
            mediaLookup: actions.mediaLookup,
            meaningNodes: actions.meaningNodes
        )
    }

    private enum PlanRow: Identifiable {
        case segment(ShotRenderPlanSegment)
        case skipped(ShotSkippedSegmentPlaceholder)

        var id: String {
            switch self {
            case .segment(let segment): return "seg_\(segment.id)"
            case .skipped(let placeholder): return "skip_\(placeholder.id)"
            }
        }
    }

    private func planRows(
        segments: [ShotRenderPlanSegment],
        placeholders: [ShotSkippedSegmentPlaceholder]
    ) -> [PlanRow] {
        var rows: [PlanRow] = []
        let byAnchor = Dictionary(grouping: placeholders, by: \.afterDisplayIndex)
        for placeholder in byAnchor[-1] ?? [] {
            rows.append(.skipped(placeholder))
        }
        for (index, segment) in segments.enumerated() {
            rows.append(.segment(segment))
            for placeholder in byAnchor[index] ?? [] {
                rows.append(.skipped(placeholder))
            }
        }
        return rows
    }

    @ViewBuilder
    var body: some View {
        if cut.renderStack.isNarrationDriven {
            narrationDrivenPlan
        } else {
            standardPlan
        }
    }

    private var standardPlan: some View {
        let plan = plan
        let generatedSeconds = plan.generatedItems.reduce(0) { $0 + $1.renderStack.segmentSeconds }
        let anotherIsRendering = !actions.activeShotRenderId.isEmpty && actions.activeShotRenderId != cut.shotId
        // Suffix context: a ready selected version with unrendered plan keys
        // offers "render only the new material"; a FAILED version with kept
        // clips offers RESUME — same law, different name. Both mark every
        // already-saved segment REUSED and price only the missing keys.
        let suffix = shotSuffixRenderPlan(shot: cut, segments: plan.segments, generatedItems: plan.generatedItems)
        let isResume = cut.activeRenderVersion?.status == "failed"
        let versionSuffixContext: ShotSuffixRenderPlan? =
            ((cut.activeRenderVersion?.isReady == true || isResume)
                && suffix.hasNewMaterial
                && suffix.reusableSegmentCount > 0)
            ? suffix : nil
        let readableSeedKeys = cutReadableSeedKeys(cut: cut)
        let combinedMissingGenerated = plan.generatedItems.filter {
            !readableSeedKeys.contains($0.pair.placementKey)
        }
        let combinedMissingKeys = Set(plan.segments.compactMap { segment -> String? in
            let key: String
            switch segment {
            case .generated(let item): key = item.pair.placementKey
            case .footage(let footage): key = footage.placementKey
            // Never in plan-generator output (assembly-only fallback band).
            case .artifactFallback: return nil
            }
            return readableSeedKeys.contains(key) ? nil : key
        })
        let combinedSuffixContext: ShotSuffixRenderPlan? =
            (!cut.combinedSources.isEmpty && !readableSeedKeys.isEmpty)
            ? ShotSuffixRenderPlan(
                missingKeys: combinedMissingKeys,
                missingGeneratedItems: combinedMissingGenerated,
                reusableSegmentCount: max(plan.segments.count - combinedMissingKeys.count, 0)
            )
            : nil
        let suffixContext = versionSuffixContext ?? combinedSuffixContext
        let itemsToGenerate = suffixContext?.missingGeneratedItems ?? plan.generatedItems
        let estimate = ShotRenderCostEstimate.estimate(
            items: itemsToGenerate,
            pricing: actions.falPricing,
            isFetchingRates: actions.isFetchingVideoPricing
        )
        let unconfiguredModels = Array(
            Set(itemsToGenerate.map(\.renderStack.model))
                .subtracting(actions.configuredRenderModels)
        ).map(\.label).sorted()
        let isCombinedSeedContext = combinedSuffixContext != nil && versionSuffixContext == nil

        return VStack(alignment: .leading, spacing: 10) {
            header(plan: plan, estimate: estimate, generatedSeconds: generatedSeconds)
            Rectangle()
                .fill(hairline(0.7))
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(planRows(segments: plan.segments, placeholders: plan.skippedPlaceholders)) { row in
                    switch row {
                    case .segment(.generated(let item)):
                        generatedRow(
                            item,
                            estimate: estimate,
                            isReused: suffixContext.map { !$0.missingKeys.contains(item.pair.placementKey) } ?? false
                        )
                    case .segment(.artifactFallback):
                        // Never in plan-generator output (assembly-only).
                        EmptyView()
                    case .segment(.footage(let segment)):
                        footageRow(
                            segment,
                            isReused: suffixContext.map {
                                !$0.missingKeys.contains(segment.placementKey)
                            } ?? false
                        )
                    case .skipped(let placeholder):
                        skippedRow(placeholder)
                    }
                }
            }
            Rectangle()
                .fill(hairline(0.7))
                .frame(height: 1)
            footer(
                plan: plan,
                estimate: estimate,
                generatedSeconds: generatedSeconds,
                unconfiguredModels: unconfiguredModels,
                anotherIsRendering: anotherIsRendering,
                suffixContext: suffixContext,
                isResume: isResume,
                isCombinedSeedContext: isCombinedSeedContext
            )
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(hairline(0.9), lineWidth: 1)
        )
        .frame(maxWidth: 720, alignment: .leading)
        // Crash-safe drafts: a debounced upsert-only autosave (see
        // mergedAutosavePromptOverrides — deletion stays a confirm/RESET
        // behavior) keyed off the raw dictionary so plan recomputes can't
        // loop it, flushed when the strip collapses.
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

    private var narrationAnchor: (entry: ShotFrameEntry, frame: ProjectLensHeroImage)? {
        shotNarrationAnchorEntry(shot: cut, frameLookup: actions.frameLookup)
    }

    /// Every entry the ANCHOR menu may offer (ready, non-skipped, non-clip).
    private var narrationAnchorCandidates: [(entry: ShotFrameEntry, frame: ProjectLensHeroImage)] {
        cut.entries.compactMap { entry in
            guard !entry.isSkipped, !entry.isClip,
                  let frame = actions.frameLookup[entry.frameImageId],
                  FileManager.default.fileExists(atPath: frame.imagePath) else { return nil }
            return (entry, frame)
        }
    }

    private var narrationDriverSeconds: Double? {
        guard let narration = cut.narrationArtifact,
              narration.isReady,
              narration.provider == "elevenlabs_tts",
              FileManager.default.fileExists(atPath: narration.audioPath) else {
            return nil
        }
        if let region = cut.audioRegions.map({ $0.normalized() }).first(where: {
            $0.laneId == ShotAudioLaneId.narration
                && $0.provenance == "active_narration"
        }) {
            return max(region.startSeconds, 0) + max(region.durationSeconds, 0)
        }
        return cut.audioMix.lane(ShotAudioLaneId.narration).effectiveStartSeconds
            + narration.durationSeconds
    }

    private var narrationPromptItem: ShotSegmentPromptPlanItem? {
        guard let anchor = narrationAnchor else { return nil }
        let pair = ShotRenderPair(
            start: anchor.frame,
            end: nil,
            startPlacementEntryId: anchor.entry.entryId,
            endPlacementEntryId: ""
        )
        return ShotSegmentPromptPlanItem(
            index: 0,
            pair: pair,
            // The narration-driven default must ASK FOR SPEECH — the generic
            // motion prompt renders a frozen mouth (two defaults, two paths).
            generatedPrompt: shotNarrationDrivenSegmentPrompt(),
            overridePrompt: cut.segmentPromptOverride(for: pair),
            renderStack: cut.renderStack,
            displayIndex: 0
        )
    }

    private var narrationDrivenPlan: some View {
        let seconds = narrationDriverSeconds
        let validDuration = seconds.map { $0 >= 2 && $0 <= 20 } == true
        let anchor = narrationAnchor
        let hasAnchor = anchor != nil
        let overrideApplies = anchor.map {
            shotAnchorFaceOverrideApplies(
                overrideEntryId: cut.narrationAnchorFaceOverrideEntryId,
                anchorEntryId: $0.entry.entryId
            )
        } ?? false
        let anchorBlocked = anchorFaceVerdict?.blocksRender == true && !overrideApplies
        let isConfigured = actions.configuredRenderModels.contains(.falLTX23Narration)
        let anotherIsRendering = !actions.activeShotRenderId.isEmpty
            && actions.activeShotRenderId != cut.shotId
        let promptItem = narrationPromptItem
        let generatedPrompt = promptItem?.generatedPrompt ?? ""
        let promptText = promptItem.map { draftValue(for: $0) } ?? ""
        let estimatedUSD = seconds.flatMap {
            ShotRenderCostEstimate.narrationDrivenUSD(
                stack: cut.renderStack,
                durationSeconds: $0,
                pricing: actions.falPricing
            )
        }
        let laterFrameCount = max(
            cut.entries.filter { !$0.isSkipped && !$0.isClip }.count - 1,
            0
        )
        let narrationIsStale = cut.activeRenderVersion.map {
            $0.model == VideoModelSelection.falLTX23AudioToVideo.providerModelId
                && (
                    (!$0.sourceNarrationFingerprint.isEmpty
                        && $0.sourceNarrationFingerprint
                            != ShotNarrationDriverBuilder.currentFingerprint(shot: cut))
                    || (!$0.sourceNarrationTraceId.isEmpty
                        && $0.sourceNarrationTraceId != cut.narrationArtifact?.traceId)
                )
        } == true

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("NARRATION VIDEO")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(labelInk)
                Text("LTX 2.3 · one shot-wide clip")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(bodyInk(0.65))
                Spacer(minLength: 0)
                if let estimatedUSD {
                    Text("EST. \(estimatedUSD < 0.01 ? String(format: "$%.3f", estimatedUSD) : String(format: "$%.2f", estimatedUSD))")
                        .font(CanonType.archive(9, weight: .bold))
                        .foregroundStyle(CanonColor.brass)
                }
            }

            if let seconds {
                Text("\(String(format: "%.1f", seconds))s authored narration drives the clip")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(validDuration ? bodyInk(0.72) : Color.red.opacity(0.8))
            } else {
                Text("A ready ElevenLabs narration is required.")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(Color.red.opacity(0.8))
            }

            if let anchor {
                anchorRow(anchor)
            }

            if !validDuration {
                HStack(spacing: 8) {
                    Text("LTX accepts 2–20 seconds. Adjust the narration region or voice speed; LitScenes will not split or trim it automatically.")
                        .font(CanonType.interface(10))
                        .foregroundStyle(bodyInk(0.64))
                    Button("OPEN NARRATION") {
                        actions.onOpenNarration(cut.shotId)
                    }
                    .buttonStyle(.borderless)
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .foregroundStyle(CanonColor.brass)
                }
            }

            if laterFrameCount > 0 {
                Text("\(laterFrameCount) other frame card\(laterFrameCount == 1 ? "" : "s") stay in the cut, but LTX uses only the ANCHOR frame above.")
                    .font(CanonType.interface(10))
                    .foregroundStyle(labelInk)
            }
            if narrationIsStale {
                Text("The active narration changed after this video version rendered. Render a new version to synchronize it.")
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.brass)
            }

            if let promptItem {
                Text("VISUAL MOTION PROMPT")
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(labelInk)
                // Must read live @State, not the `promptText` snapshot captured above:
                // a stale getter makes TextEditor reassign its string after every
                // keystroke, which collapses the selection to the end of the box.
                TextEditor(text: draftBinding(for: promptItem))
                .font(CanonType.interface(11))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 58, maxHeight: 86)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(narrationEditorFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(hairline(), lineWidth: 1)
                )
            }

            HStack(spacing: 8) {
                Button("CANCEL", action: onCancel)
                    .buttonStyle(.borderless)
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .foregroundStyle(labelInk)
                Spacer(minLength: 0)
                Button("RENDER ONE CLIP") {
                    guard let promptItem else { return }
                    var items = [promptItem]
                    items.append(contentsOf: plan.generatedItems.filter {
                        $0.pair.placementKey != promptItem.pair.placementKey
                    })
                    let promptDrafts = drafts.merging([
                        promptItem.pairKey: promptText.trimmed.isEmpty
                            ? generatedPrompt
                            : promptText
                    ]) { _, new in new }
                    onConfirm(
                        computedSegmentPromptOverrides(
                            drafts: promptDrafts,
                            items: items,
                            now: DateFormats.now()
                        ),
                        nil
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(CanonColor.brass)
                .disabled(
                    !hasAnchor
                        || !validDuration
                        || !isConfigured
                        || anotherIsRendering
                        || promptItem == nil
                        || anchorBlocked
                )
                .help(anchorBlocked
                    ? (anchorFaceVerdict.flatMap { shotAnchorLipSyncRefusal(verdict: $0) } ?? "")
                    : "One paid LTX 2.3 request for the whole shot")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(hairline(0.9), lineWidth: 1)
        )
        .frame(maxWidth: 720, alignment: .leading)
        .task(id: anchor?.frame.imagePath ?? "") {
            anchorFaceVerdict = nil
            guard let path = anchor?.frame.imagePath else { return }
            let report = await Task.detached(priority: .utility) {
                shotAnchorFaceReport(imagePath: path)
            }.value
            anchorFaceVerdict = shotAnchorLipSyncVerdict(report: report)
        }
    }

    /// The ANCHOR row: which frame the one clip grows from, a picker over the
    /// ready frames, and the local face verdict that gates the render.
    private func anchorRow(_ anchor: (entry: ShotFrameEntry, frame: ProjectLensHeroImage)) -> some View {
        let candidates = narrationAnchorCandidates
        let currentIndex = candidates.firstIndex { $0.entry.entryId == anchor.entry.entryId }
        let overrideApplies = shotAnchorFaceOverrideApplies(
            overrideEntryId: cut.narrationAnchorFaceOverrideEntryId,
            anchorEntryId: anchor.entry.entryId
        )
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                miniThumb(anchor.frame)
                Menu {
                    ForEach(Array(candidates.enumerated()), id: \.element.entry.entryId) { index, candidate in
                        Button {
                            actions.onSetNarrationAnchor(cut.shotId, candidate.entry.entryId)
                        } label: {
                            Text("FRAME \(index + 1)\(candidate.entry.entryId == anchor.entry.entryId ? " ✓" : "")")
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "scope")
                            .font(.system(size: 8, weight: .semibold))
                        Text("ANCHOR · FRAME \((currentIndex ?? 0) + 1)")
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .kerning(0.5)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .semibold))
                    }
                    .foregroundStyle(bodyInk(0.65))
                    .padding(.horizontal, 7)
                    .frame(height: 22)
                    .background(Capsule().fill(chipFill(0.6)))
                    .overlay(Capsule().stroke(hairline(0.8), lineWidth: 1))
                }
                .modifier(CutStripMenuChipStyle(isPlate: isPlate))
                .fixedSize()
                .disabled(candidates.count <= 1)
                .help(candidates.count <= 1
                    ? "The one ready frame anchors the clip"
                    : "Pick which frame anchors the one narration clip")
                faceVerdictChip(overrideApplies: overrideApplies)
                Spacer(minLength: 0)
            }
            if !overrideApplies,
               let verdict = anchorFaceVerdict,
               let refusal = shotAnchorLipSyncRefusal(verdict: verdict) {
                Text(refusal)
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.rust)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    actions.onSetNarrationAnchorFaceOverride(cut.shotId, anchor.entry.entryId)
                } label: {
                    Text("RENDER ANYWAY — I CAN SEE THE FACE")
                        .font(CanonType.archive(7, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.brass)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(CanonColor.brass.opacity(0.10)))
                        .overlay(Capsule().stroke(CanonColor.brass.opacity(0.45), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Vision missed the face (stylized frames especially). Vouch for this frame — the check stays off for it until you pick a different anchor.")
            }
        }
    }

    @ViewBuilder
    private func faceVerdictChip(overrideApplies: Bool) -> some View {
        if overrideApplies, anchorFaceVerdict?.blocksRender == true {
            // The vouch, visible and one click from re-arming. Inert on a
            // passing frame — the normal chips tell the truth there.
            Button {
                actions.onSetNarrationAnchorFaceOverride(cut.shotId, "")
            } label: {
                verdictChip("FACE CHECK OVERRIDDEN", color: CanonColor.brass.opacity(0.75))
            }
            .buttonStyle(.plain)
            .help("You vouched for this frame. Click to re-arm the face check.")
        } else {
            switch anchorFaceVerdict {
            case .ready(let fraction):
                verdictChip("FACE ≈\(Int((fraction * 100).rounded()))% · LIP-SYNC READY", color: CanonColor.brass)
            case .small(let fraction):
                verdictChip("FACE ≈\(Int((fraction * 100).rounded()))% · TOO SMALL", color: CanonColor.rust)
            case .noFace:
                verdictChip("NO FACE", color: CanonColor.rust)
            case .unavailable:
                verdictChip("FACE CHECK UNAVAILABLE — RENDER ALLOWED", color: CanonColor.muted)
            case nil:
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("CHECKING FACE")
                        .font(CanonType.archive(6.5, weight: .semibold))
                        .kerning(0.5)
                        .foregroundStyle(labelInk)
                }
            }
        }
    }

    private func verdictChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(CanonType.archive(6.5, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.12)))
    }

    private func autosaveDrafts() {
        let computed = computedSegmentPromptOverrides(
            drafts: drafts,
            items: plan.generatedItems,
            now: DateFormats.now()
        )
        let merged = mergedAutosavePromptOverrides(existing: cut.segmentPromptOverrides, computed: computed)
        if !promptOverridesAgree(merged, cut.segmentPromptOverrides) {
            actions.onAutosavePromptOverrides(cut.shotId, merged)
        }
        let mergedPlans = mergedAutosaveDirectionPlans(
            existing: cut.segmentDirectionPlans,
            computed: computedPlans()
        )
        if !directionPlansAgree(mergedPlans, cut.segmentDirectionPlans) {
            actions.onSaveDirectionPlans(cut.shotId, mergedPlans)
        }
    }

    /// The shared pure sibling of `computedSegmentPromptOverrides`, so the
    /// strip and the Re-render panel persist plans identically.
    private func computedPlans() -> [ShotSegmentDirectionPlanRecord] {
        computedSegmentDirectionPlans(
            planDrafts: planDrafts,
            modeDrafts: modeDrafts,
            items: plan.generatedItems,
            existing: cut.segmentDirectionPlans,
            now: DateFormats.now()
        )
    }

    /// Confirm-time persist: plans first, then overrides ride onConfirm.
    private func saveDirectionPlansForConfirm() {
        actions.onSaveDirectionPlans(cut.shotId, computedPlans())
    }

    // MARK: Header / footer

    private func header(
        plan: (segments: [ShotRenderPlanSegment], generatedItems: [ShotSegmentPromptPlanItem], skipped: [String], strands: [MeaningStrand], skippedPlaceholders: [ShotSkippedSegmentPlaceholder]),
        estimate: ShotRenderCostEstimate,
        generatedSeconds: Int
    ) -> some View {
        HStack(spacing: 8) {
            if isPlate {
                // The plate's header IS the picker: what the next render uses
                // sits where the plan is confirmed, and the footer already
                // states the recipe and length.
                renderStackChip
            } else {
                Text("RENDER PLAN")
                    .font(CanonType.archive(7.5, weight: .semibold))
                    .kerning(1.1)
                    .foregroundStyle(labelInk)
                Text("\(plan.generatedItems.count) generated segment\(plan.generatedItems.count == 1 ? "" : "s") · ~\(generatedSeconds)s video")
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(bodyInk(0.65))
            }
            Spacer(minLength: 0)
            if let headline = estimate.headlineLabel {
                Text(headline)
                    .font(CanonType.archive(9, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(CanonColor.brass)
                    .help(estimateHelp(estimate))
            }
            if estimate.isFetchingRates {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("FETCHING RATES")
                        .font(CanonType.archive(7, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(labelInk)
                }
            } else if let snapshot = actions.falPricing {
                Text("rates from FAL · \(snapshot.ageLabel)")
                    .font(CanonType.interface(9.5))
                    .foregroundStyle(quiet(0.75))
                    .help("Live FAL platform rates, re-checked when over a day old")
            } else if estimate.headlineLabel == nil {
                Text("rates unavailable")
                    .font(CanonType.interface(9.5))
                    .foregroundStyle(quiet(0.75))
                    .help("FAL rates could not be fetched — rendering still works; the estimate appears once rates load")
            }
        }
    }

    /// The NEXT-render stack picker on the plate — the same items as the
    /// row's chip, labelled NEXT whenever it disagrees with what the playable
    /// version was actually rendered with.
    private var renderStackChip: some View {
        let provenance = cut.playableRenderVersion.map { shotRenderProvenanceSummary(version: $0) }
        let nextDiffers = provenance.map { $0 != cut.renderStack.shortLabel } ?? false
        return Menu {
            ShotRenderStackMenuContent(cut: cut, actions: actions)
        } label: {
            HStack(spacing: 5) {
                Text(nextDiffers ? "NEXT · \(cut.renderStack.shortLabel)" : cut.renderStack.shortLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .font(CanonType.archive(8.5, weight: .bold))
            .kerning(0.8)
            .foregroundStyle(ScenesV2StageDress.ink)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(chipFill(0.6)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(hairline(), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("\(cut.renderStack.accurateHelp) Sets this render's model and length — segment overrides remain independent.")
    }

    private func estimateHelp(_ estimate: ShotRenderCostEstimate) -> String {
        if estimate.isComplete {
            if estimate.includesPublishedRateEstimate {
                return "Approximate total: LTX Native Extend uses its published 1080p per-second rate; FAL segments use live rates. Provider billing is authoritative."
            }
            return "Estimated from live FAL rates — provider billing is authoritative"
        }
        let missing = estimate.unpricedModelLabels.joined(separator: ", ")
        return "Partial estimate — no rate available for: \(missing)."
    }

    private func footer(
        plan: (segments: [ShotRenderPlanSegment], generatedItems: [ShotSegmentPromptPlanItem], skipped: [String], strands: [MeaningStrand], skippedPlaceholders: [ShotSkippedSegmentPlaceholder]),
        estimate: ShotRenderCostEstimate,
        generatedSeconds: Int,
        unconfiguredModels: [String],
        anotherIsRendering: Bool,
        suffixContext: ShotSuffixRenderPlan? = nil,
        isResume: Bool = false,
        isCombinedSeedContext: Bool = false
    ) -> some View {
        let recipeSummary = renderRecipeSummary(items: plan.generatedItems)
        let confirmTitle = estimate.headlineLabel.map { "RENDER · \($0)" } ?? "RENDER"
        let leadInItems = suffixContext?.missingGeneratedItems ?? plan.generatedItems
        let leadInBlockedModels = Set(
            leadInItems
                .filter { $0.pair.start == nil && $0.renderStack.tailAnchoredModelSelection == nil }
                .map(\.renderStack.model.label)
        ).sorted()
        let nativeExtendBlocked = leadInItems.contains {
            $0.renderStack.isNativeFootageExtend && !$0.canUseNativeFootageExtend
        }
        return HStack(spacing: 10) {
            Text("\(recipeSummary) = \(generatedSeconds)s generated")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(labelInk)
            Spacer(minLength: 0)
            Button {
                onCancel()
            } label: {
                Text("CANCEL")
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(labelInk)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(ghostTint.opacity(0.08)))
                    .overlay(Capsule().stroke(ghostTint.opacity(0.4), lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            if let suffix = suffixContext {
                // Two honest choices: pay only for the new material (saved
                // clips reused verbatim), or re-render the whole plan.
                let newEstimate = ShotRenderCostEstimate.estimate(
                    items: suffix.missingGeneratedItems,
                    pricing: actions.falPricing,
                    isFetchingRates: actions.isFetchingVideoPricing
                )
                Button {
                    let allKeys = Set(plan.segments.compactMap { segment -> String? in
                        switch segment {
                        case .generated(let item): return item.pair.placementKey
                        case .footage(let footage): return footage.placementKey
                        // Never in plan-generator output (assembly-only).
                        case .artifactFallback: return nil
                        }
                    })
                    saveDirectionPlansForConfirm()
                    onConfirm(
                        computedSegmentPromptOverrides(drafts: drafts, items: plan.generatedItems, now: DateFormats.now()),
                        allKeys
                    )
                } label: {
                    Text("RE-RENDER ALL\(estimate.headlineLabel.map { " · \($0)" } ?? "")")
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(0.6)
                        .foregroundStyle(labelInk)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(ghostTint.opacity(0.08)))
                        .overlay(Capsule().stroke(ghostTint.opacity(0.4), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!unconfiguredModels.isEmpty
                    || !leadInBlockedModels.isEmpty
                    || nativeExtendBlocked
                    || anotherIsRendering)
                .help("Regenerate every segment from scratch at full cost")
                confirmButton(
                    title: {
                        if isCombinedSeedContext && suffix.missingKeys.isEmpty {
                            return "FINALIZE · $0"
                        }
                        let verb = isResume
                            ? "RESUME"
                            : (isCombinedSeedContext ? "RENDER MISSING" : "RENDER NEW MATERIAL")
                        return newEstimate.headlineLabel.map { "\(verb) · \($0)" } ?? verb
                    }(),
                    enabled: unconfiguredModels.isEmpty
                        && leadInBlockedModels.isEmpty
                        && !nativeExtendBlocked
                        && !anotherIsRendering,
                    help: nativeExtendBlocked
                        ? "Native Extend needs an AI extension directly after at least 73 frames of footage — choose Out-frame above"
                        : (!leadInBlockedModels.isEmpty
                        ? "\(leadInBlockedModels.joined(separator: ", ")) can't render an AI lead-in — it needs a model that accepts a tail frame alone"
                        : (!unconfiguredModels.isEmpty
                            ? "Configure \(unconfiguredModels.joined(separator: ", ")) in App Settings before rendering"
                            : (anotherIsRendering
                                ? "Another cut is rendering"
                                : (isCombinedSeedContext && suffix.missingKeys.isEmpty
                                    ? "All source video is reusable — assemble a ready version locally for $0"
                                    : "\(isResume ? "Resume renders" : "Render") only the \(suffix.missingKeys.count) missing segment\(suffix.missingKeys.count == 1 ? "" : "s") — the \(suffix.reusableSegmentCount) saved one\(suffix.reusableSegmentCount == 1 ? " is" : "s are") reused verbatim. A new version is created."))))
                ) {
                    saveDirectionPlansForConfirm()
                    onConfirm(
                        computedSegmentPromptOverrides(drafts: drafts, items: plan.generatedItems, now: DateFormats.now()),
                        isCombinedSeedContext && suffix.missingKeys.isEmpty
                            ? nil
                            : suffix.missingKeys
                    )
                }
            } else {
                confirmButton(
                    title: confirmTitle,
                    enabled: unconfiguredModels.isEmpty
                        && leadInBlockedModels.isEmpty
                        && !nativeExtendBlocked
                        && !anotherIsRendering
                        && !(plan.generatedItems.isEmpty && plan.segments.isEmpty),
                    help: nativeExtendBlocked
                        ? "Native Extend needs an AI extension directly after at least 73 frames of footage — choose Out-frame above"
                        : (!leadInBlockedModels.isEmpty
                        ? "\(leadInBlockedModels.joined(separator: ", ")) can't render an AI lead-in — it needs a model that accepts a tail frame alone"
                        : (!unconfiguredModels.isEmpty
                            ? "Configure \(unconfiguredModels.joined(separator: ", ")) in App Settings before rendering"
                            : (anotherIsRendering
                                ? "Another cut is rendering"
                                : "Save these prompts and render — exactly what's shown above is what runs")))
                ) {
                    saveDirectionPlansForConfirm()
                    onConfirm(
                        computedSegmentPromptOverrides(drafts: drafts, items: plan.generatedItems, now: DateFormats.now()),
                        nil
                    )
                }
            }
        }
    }

    private func confirmButton(
        title: String,
        enabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .semibold))
                Text(title)
                    .font(CanonType.archive(8, weight: .bold))
                    .kerning(0.6)
            }
            .foregroundStyle(confirmInk)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Capsule().fill(CanonColor.brass.opacity(enabled ? 1 : 0.45)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func renderRecipeSummary(items: [ShotSegmentPromptPlanItem]) -> String {
        let stacks = Set(items.map(\.renderStack))
        if stacks.count == 1, let only = stacks.first {
            return "\(items.count) × \(only.segmentSeconds)s \(only.model.label)"
        }
        return "\(items.count) segments · mixed recipes"
    }

    // MARK: Rows

    private func generatedRow(_ item: ShotSegmentPromptPlanItem, estimate: ShotRenderCostEstimate, isReused: Bool = false) -> some View {
        let configured = actions.configuredRenderModels.contains(item.renderStack.model)
        let segmentUSD = ShotRenderCostEstimate.segmentUSD(item: item, pricing: actions.falPricing)
        return HStack(alignment: .top, spacing: 10) {
            pairThumbs(item.pair)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("SEGMENT \(item.displayIndex + 1) · \(item.renderStack.model.label) · \(item.renderStack.segmentSeconds)s\(item.renderStack.generateAudio ? " · AUDIO" : "")")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .kerning(0.7)
                        .foregroundStyle(bodyInk(0.7))
                    if isReused {
                        Text("REUSED · $0")
                            .font(CanonType.archive(6.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(CanonColor.brass)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(CanonColor.brass.opacity(0.12)))
                            .help("This segment's saved clip is reused verbatim by RENDER NEW MATERIAL — RE-RENDER ALL to regenerate it")
                    }
                    if item.hasRenderOverride {
                        Text("OVERRIDDEN RECIPE")
                            .font(CanonType.archive(6.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(CanonColor.brass)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(CanonColor.brass.opacity(0.12)))
                    }
                    if item.pair.start == nil, item.renderStack.tailAnchoredModelSelection == nil {
                        Text("NO LEAD-IN MODEL")
                            .font(CanonType.archive(6.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(CanonColor.rust)
                            .help("\(item.renderStack.model.label) can't render an end-anchored lead-in — it needs a model that accepts a tail frame alone")
                    }
                    if !configured {
                        Text("NEEDS API KEY")
                            .font(CanonType.archive(6.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(CanonColor.rust)
                    }
                    Spacer(minLength: 0)
                    if isReused {
                        EmptyView()
                    } else if let segmentUSD {
                        Text(segmentUSD < 0.01 && segmentUSD > 0 ? String(format: "$%.3f", segmentUSD) : String(format: "$%.2f", segmentUSD))
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .kerning(0.4)
                            .foregroundStyle(CanonColor.brass.opacity(0.9))
                            .help(item.renderStack.isNativeFootageExtend
                                ? "Approximate LTX published rate: $0.10 per generated plus context second at 1920×1080; provider billing is authoritative"
                                : (item.renderStack.generateAudio
                                    ? "Live FAL rate; native audio may affect provider billing"
                                    : "Live FAL rate"))
                    } else if estimate.isFetchingRates {
                        Text("…")
                            .font(CanonType.archive(7.5, weight: .semibold))
                            .foregroundStyle(labelInk)
                    } else {
                        Text("RATE N/A")
                            .font(CanonType.archive(6.5, weight: .semibold))
                            .kerning(0.4)
                            .foregroundStyle(quiet(0.75))
                            .help("No FAL rate available for this model yet")
                    }
                }
                if item.isAIExtension {
                    extensionContinuityControls(item)
                }
                if isReused {
                    // A reused segment's prompt is history, not intent — no
                    // beats editing on material that will not re-render.
                    TextEditor(text: draftBinding(for: item))
                        .font(CanonType.interface(11))
                        .foregroundStyle(labelInk)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(height: 84)
                        .background(RoundedRectangle(cornerRadius: 7).fill(reusedEditorFill))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(hairline(0.9), lineWidth: 1)
                        )
                        .disabled(true)
                        .help("Reused verbatim from the selected version — RE-RENDER ALL to reprompt this segment")
                } else {
                    ShotSegmentBeatsEditor(
                        item: item,
                        plan: planBinding(for: item),
                        mode: modeBinding(for: item),
                        isDrafting: actions.draftingDirectionKeys.contains("\(cut.shotId)|\(item.pairKey)"),
                        draftError: actions.directionDraftErrors["\(cut.shotId)|\(item.pairKey)"],
                        onDraft: { actions.onDraftDirectionPlan(cut.shotId, item.pairKey) }
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            TextEditor(text: draftBinding(for: item))
                                .font(CanonType.interface(11))
                                .foregroundStyle(CanonColor.ink)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .frame(height: 84)
                                .background(RoundedRectangle(cornerRadius: 7).fill(editorFill))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(isEdited(item) ? CanonColor.brass.opacity(0.55) : hairline(0.9), lineWidth: 1)
                                )
                            if isEdited(item) {
                                Button {
                                    drafts[item.pairKey] = item.generatedPrompt
                                } label: {
                                    Text("RESET TO GENERATED")
                                        .font(CanonType.archive(6.5, weight: .bold))
                                        .kerning(0.5)
                                        .foregroundStyle(labelInk)
                                }
                                .buttonStyle(.plain)
                                .help("Discard your edit — the generated prompt renders")
                            }
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(item.pair.placementKey == focusedSegmentKey
                    ? CanonColor.brass.opacity(0.10)
                    : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(item.pair.placementKey == focusedSegmentKey
                    ? CanonColor.brass.opacity(0.55)
                    : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func extensionContinuityControls(_ item: ShotSegmentPromptPlanItem) -> some View {
        let usesNative = item.renderStack.isNativeFootageExtend
        HStack(spacing: 7) {
            Text("CONTINUITY")
                .font(CanonType.archive(6.5, weight: .bold))
                .kerning(0.55)
                .foregroundStyle(labelInk)
            Menu {
                Button {
                    let defaultStack = cut.renderStack.isNarrationDriven
                        ? ShotRenderStack.fallback
                        : cut.renderStack
                    actions.onSetSegmentRenderStack(
                        cut.shotId,
                        item.pair,
                        defaultStack == cut.renderStack ? nil : defaultStack
                    )
                } label: {
                    if !usesNative {
                        Label("Out-frame · image-to-video", systemImage: "checkmark")
                    } else {
                        Text("Out-frame · image-to-video")
                    }
                }

                Button {
                    actions.onSetSegmentRenderStack(
                        cut.shotId,
                        item.pair,
                        ShotRenderStack.recipe(
                            model: .ltx23NativeExtend,
                            durationSeconds: item.renderStack.model == .ltx23NativeExtend
                                ? item.renderStack.segmentSeconds
                                : 8
                        )
                    )
                } label: {
                    if usesNative {
                        Label("Native Extend · video-to-video", systemImage: "checkmark")
                    } else {
                        Text(actions.configuredRenderModels.contains(.ltx23NativeExtend)
                            ? "Native Extend · video-to-video"
                            : "Native Extend · needs LTX API key")
                    }
                }
                .disabled(!item.canUseNativeFootageExtend
                    || !actions.configuredRenderModels.contains(.ltx23NativeExtend))
            } label: {
                HStack(spacing: 4) {
                    Text(usesNative ? "NATIVE EXTEND" : "OUT-FRAME")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                }
                .font(CanonType.archive(7, weight: .semibold))
                .foregroundStyle(bodyInk(0.78))
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: 4).fill(chipFill(0.55)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(hairline(), lineWidth: 1))
            }
            .modifier(CutStripMenuChipStyle(isPlate: isPlate))
            .menuIndicator(.hidden)
            .fixedSize()
            .help(item.canUseNativeFootageExtend
                ? "Out-frame animates the clip's last still. Native Extend sends the exact placed video range to LTX and preserves its audio continuity."
                : "Native Extend needs this extension to sit directly after at least 73 frames of placed footage. Out-frame remains available.")

            if usesNative {
                Menu {
                    ForEach(ShotRenderModel.ltx23NativeExtend.supportedDurations, id: \.self) { seconds in
                        Button {
                            actions.onSetSegmentRenderStack(
                                cut.shotId,
                                item.pair,
                                item.renderStack.replacingDuration(seconds)
                            )
                        } label: {
                            if seconds == item.renderStack.segmentSeconds {
                                Label("\(seconds)s", systemImage: "checkmark")
                            } else {
                                Text("\(seconds)s")
                            }
                        }
                    }
                } label: {
                    Text("\(item.renderStack.segmentSeconds)S")
                        .font(CanonType.archive(7, weight: .semibold))
                        .foregroundStyle(bodyInk(0.78))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(chipFill(0.55)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(hairline(), lineWidth: 1))
                }
                .modifier(CutStripMenuChipStyle(isPlate: isPlate))
                .menuIndicator(.hidden)
                .fixedSize()

                if let context = item.nativeExtendContextSeconds {
                    Text("\(String(format: "%.1f", context))s context · audio retained")
                        .font(CanonType.archive(6.5, weight: .medium))
                        .foregroundStyle(labelInk)
                } else {
                    Text("SOURCE TOO SHORT")
                        .font(CanonType.archive(6.5, weight: .bold))
                        .foregroundStyle(CanonColor.rust)
                }
            }
            Spacer(minLength: 0)
        }
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

    /// The eject law, identical to the Re-render panel: beats→raw seeds the
    /// raw box with the compiled text; raw→beats restores the retained plan.
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

    private func footageRow(_ segment: ShotFootagePlanSegment, isReused: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(quiet(0.8))
            Text("FOOTAGE · \(segment.clip.filename) · \(videoTrimTimestampLabel(segment.clip.resolvedDurationSeconds)) plays verbatim · \(isReused ? "REUSED" : "LOCAL") · $0")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.5)
                .foregroundStyle(labelInk)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func skippedRow(_ placeholder: ShotSkippedSegmentPlaceholder) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(quiet(0.55))
            Text("SKIPPED · \(placeholder.label) — contributes nothing to this render")
                .font(CanonType.archive(7, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(quiet(0.7))
            Spacer(minLength: 0)
        }
    }

    // MARK: Pair thumbs

    private func pairThumbs(_ pair: ShotRenderPair) -> some View {
        HStack(spacing: 4) {
            if let start = pair.start {
                miniThumb(start)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(hairline(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 48, height: 27)
                    .overlay(
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(quiet(0.7))
                    )
                    .help("Lead-in — begins in generated motion and arrives on the next frame")
            }
            Image(systemName: "arrow.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(quiet(0.7))
            if let end = pair.end {
                miniThumb(end)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(hairline(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(width: 48, height: 27)
                    .overlay(
                        Image(systemName: "infinity")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(quiet(0.7))
                    )
                    .help("Open-ended — continues from the start frame with no destination keyframe")
            }
        }
        .padding(.top, 2)
    }

    private func miniThumb(_ frame: ProjectLensHeroImage) -> some View {
        ZStack {
            CanonColor.mediaCardHover
            if frame.provider == "footage" {
                Image(systemName: "film")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CanonColor.bone.opacity(0.85))
            } else if !frame.imagePath.trimmed.isEmpty,
                      let image = NSImage(contentsOfFile: frame.imagePath) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(quiet(0.7))
            }
        }
        .frame(width: 48, height: 27)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(hairline(0.9), lineWidth: 1))
        .help(frame.provider == "footage" ? "Footage boundary still" : frame.label)
    }

    // MARK: Drafts
    //
    // Drafts are lazy and pair-keyed: a box the user never touched reads
    // override-else-generated straight from the live plan, so structural
    // edits to the cut while the strip is open (insert, reorder, skip) can
    // never orphan a draft or blank a row — the plan recomputes, the pair
    // keys hold, and untouched pairs carry their persisted overrides through
    // the save (the law in `computedSegmentPromptOverrides`).

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
}
