import SwiftUI

/// The structured beats editor for one render segment — the shared component
/// both prompt surfaces (the Re-render panel and the inline render-plan
/// strip) embed in place of their bare prompt box. Owns the BEATS|RAW mode
/// chips; in beats mode it edits the segment's temporal direction plan and
/// previews the compiled dialect live, in raw mode it renders the surface's
/// own classic `TextEditor` untouched. The mode binding's setter (owned by
/// the surface) implements the eject law: beats→raw seeds the raw box with
/// the compiled text; raw→beats restores the retained plan.
struct ShotSegmentBeatsEditor<RawEditor: View>: View {
    let item: ShotSegmentPromptPlanItem
    @Binding var plan: ShotTemporalDirectionPlan
    @Binding var mode: ShotSegmentPromptMode
    /// LLM drafting lane state for THIS segment (on-demand only — nothing
    /// drafts on open).
    var isDrafting: Bool = false
    var draftError: String? = nil
    var onDraft: () -> Void = {}
    @ViewBuilder var rawEditor: () -> RawEditor

    /// Hand-authored beats share the LLM clamp — four is the ceiling.
    private static var beatCap: Int { 4 }

    private var segmentSeconds: Int { item.renderStack.segmentSeconds }

    private var modelSelection: VideoModelSelection? {
        item.renderStack.modelSelection(for: item.pair)
    }

    /// The DRAFT plan compiled live — what a render confirmed right now
    /// would send, ahead of the debounced autosave.
    private var liveCompiled: ShotCompiledSegmentDirection? {
        guard let modelSelection else { return nil }
        return compileTemporalDirection(
            plan: plan,
            modelSelection: modelSelection,
            durationSeconds: segmentSeconds
        )
    }

    private var windows: [ShotAllocatedBeat] {
        shotTemporalBeatAllocation(plan: plan, totalSeconds: segmentSeconds)
    }

    private var fallbackPlan: ShotTemporalDirectionPlan {
        shotFallbackDirectionPlan(pair: item.pair)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            modeRow
            draftErrorLine
            if mode == .beats, modelSelection != nil {
                shotModeRow
                beatRows
                compiledPreview
            } else {
                rawEditor()
            }
        }
    }

    private var modeRow: some View {
        HStack(spacing: 6) {
            // A lead-in with no tail-capable model has nothing to compile —
            // the beats chip stays honest and absent.
            if modelSelection != nil {
                Button("Beats") { mode = .beats }
                    .buttonStyle(PlateButtonStyle(isProminent: mode == .beats))
                    .help("Direct this segment as timed action beats, compiled into each model's own timing dialect")
                Button("Raw") { mode = .raw }
                    .buttonStyle(PlateButtonStyle(isProminent: mode == .raw))
                    .help("Type the prompt yourself — switching seeds the box with the compiled beats text")
            }
            Spacer(minLength: 0)
            if mode == .beats {
                if item.directionPlanIsStale {
                    PlateLabel(text: "STALE", size: 7.5, weight: .semibold, color: CanonColor.rust)
                        .help("The frames, narration, or duration behind this LLM draft changed — the beats still render; re-draft to catch up")
                }
                if isDrafting {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                } else {
                    Button(item.directionPlan?.llmDraftPlan != nil ? "Re-draft" : "Draft beats") {
                        onDraft()
                    }
                    .buttonStyle(PlateButtonStyle())
                    .help("Have the LLM draft this segment's beats from the keyframes, lineage, and narration — you edit the result; nothing renders")
                }
                beatsResetMenu
            }
        }
    }

    @ViewBuilder
    private var draftErrorLine: some View {
        if let draftError, mode == .beats {
            PlateLabel(text: draftError, size: 8, color: CanonColor.rust)
                .help("The last beat draft failed — the beats shown are unchanged; Draft beats retries")
        }
    }

    private var beatsResetMenu: some View {
        Menu {
            if let llmDraft = item.directionPlan?.llmDraftPlan, !llmDraft.isEmpty {
                Button("Reset to drafted beats") { plan = llmDraft }
            }
            Button("Reset to default") { plan = fallbackPlan }
        } label: {
            HStack(spacing: 4) {
                Text("Reset")
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Return this segment's beats to the LLM draft or the one-beat default")
    }

    private var shotModeRow: some View {
        HStack(spacing: 6) {
            Button("Continuous") { plan.shotMode = .continuous }
                .buttonStyle(PlateButtonStyle(isProminent: plan.shotMode == .continuous))
                .help("One unbroken take — beats pace the motion, never cut the camera")
            Button("Multi-shot") { plan.shotMode = .multiShot }
                .buttonStyle(PlateButtonStyle(isProminent: plan.shotMode == .multiShot))
                .help("Deliberate hard cuts between beats, on models that support them (Kling 3 sends a native shot array)")
            Spacer(minLength: 0)
        }
    }

    private var beatRows: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(plan.beats.indices, id: \.self) { index in
                beatRow(index)
            }
            if plan.beats.count < Self.beatCap {
                Button("+ Beat") {
                    plan.beats.append(ShotTemporalBeat())
                }
                .buttonStyle(PlateButtonStyle())
                .help("Add an action beat (up to \(Self.beatCap))")
            }
        }
    }

    private func beatRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: 7) {
            PlateLabel(
                text: windowText(index),
                size: 8,
                weight: .semibold,
                color: PlateColor.inkFaint
            )
            .frame(width: 44, alignment: .leading)
            .padding(.top, 5)
            .help("Target window from the beat weights and the \(segmentSeconds)s segment — a guide for the model, not a frame-accurate edit point")
            weightStepper(index)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                TextField("What moves", text: beatBinding(index, \.action), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(PlateType.label(11, weight: .regular))
                    .foregroundStyle(PlateColor.ink)
                    .lineLimit(1...3)
                TextField("Camera — optional", text: beatBinding(index, \.camera))
                    .textFieldStyle(.plain)
                    .font(PlateType.label(10, weight: .regular))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline, lineWidth: 1))
            VStack(spacing: 2) {
                Button {
                    plan.beats.swapAt(index, index - 1)
                } label: {
                    Image(systemName: "chevron.up").font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(index == 0)
                Button {
                    plan.beats.swapAt(index, index + 1)
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(index == plan.beats.count - 1)
                Button {
                    plan.beats.remove(at: index)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(plan.beats.count <= 1)
                .help("Remove this beat")
            }
            .foregroundStyle(PlateColor.inkFaint)
            .padding(.top, 4)
        }
    }

    private func windowText(_ index: Int) -> String {
        // The allocation may merge trailing beats when they outnumber the
        // seconds — only aligned windows wear exact plates.
        guard windows.count == plan.beats.count, windows.indices.contains(index) else { return "~" }
        return "\(windows[index].startSecond)–\(windows[index].endSecond)s"
    }

    private func weightStepper(_ index: Int) -> some View {
        HStack(spacing: 3) {
            Button {
                plan.beats[index].durationWeight = max(plan.beats[index].sanitizedWeight - 1, 1)
            } label: {
                Image(systemName: "minus").font(.system(size: 6, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(plan.beats[index].sanitizedWeight <= 1)
            Text("×\(Int(plan.beats[index].sanitizedWeight))")
                .font(PlateType.label(9, weight: .semibold))
                .frame(width: 20)
            Button {
                plan.beats[index].durationWeight = min(plan.beats[index].sanitizedWeight + 1, 4)
            } label: {
                Image(systemName: "plus").font(.system(size: 6, weight: .bold))
            }
            .buttonStyle(.plain)
            .disabled(plan.beats[index].sanitizedWeight >= 4)
        }
        .foregroundStyle(PlateColor.ink)
        .padding(.horizontal, 5)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.65)))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(PlateColor.hairline, lineWidth: 1))
        .help("This beat's share of the segment, relative to the others")
    }

    @ViewBuilder
    private var compiledPreview: some View {
        if let compiled = liveCompiled {
            VStack(alignment: .leading, spacing: 3) {
                PlateLabel(
                    text: dialectCaption(compiled),
                    size: 7.5,
                    color: PlateColor.inkFaint
                )
                Text(compiled.canonicalText)
                    .font(PlateType.label(10, weight: .regular))
                    .foregroundStyle(PlateColor.ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 3).fill(PlateColor.creamDeep.opacity(0.35)))
            }
            .help("Exactly what the next render sends for this segment — compiled from the beats for \(item.renderStack.model.label)")
        } else {
            PlateLabel(
                text: "Add an action to at least one beat — empty beats render the classic default sentence",
                size: 8,
                color: PlateColor.inkFaint
            )
        }
    }

    private func dialectCaption(_ compiled: ShotCompiledSegmentDirection) -> String {
        let model = item.renderStack.model.label
        switch compiled.dialect {
        case "seedance25_intervals": return "Sent to \(model) as second-stamped intervals"
        case "kling_timed_prose": return "Sent to \(model) as timed prose · one continuous take"
        case "kling_multi_prompt": return "Sent to \(model) as \(compiled.klingShots?.count ?? 0) native timed prompts"
        case "wan_shots": return "Sent to \(model) as shot-stamped direction"
        case "seedance20_ordered": return "Sent to \(model) as ordered actions — no timestamps (2.0 treats exact seconds as unstable)"
        default: return "Sent to \(model) as soft ordered motion"
        }
    }

    private func beatBinding(_ index: Int, _ keyPath: WritableKeyPath<ShotTemporalBeat, String>) -> Binding<String> {
        Binding(
            get: { plan.beats.indices.contains(index) ? plan.beats[index][keyPath: keyPath] : "" },
            set: { newValue in
                guard plan.beats.indices.contains(index) else { return }
                plan.beats[index][keyPath: keyPath] = newValue
            }
        )
    }
}
