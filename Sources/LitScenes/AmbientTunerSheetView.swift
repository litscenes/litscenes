import AppKit
import SwiftUI

/// The Ambient Bed Tuner — an engraved-plate instrument for dialing a
/// white-noise-like bed: a precise log-scale frequency ruler with magnetic
/// detents, a WIDTH control, four filter dials (WARMTH / DRIFT / CRACKLE /
/// WASH), a live audition engine, and a shelf of the project's baked beds.
/// Hosted as a nested sheet of the shot player modal.
struct AmbientTunerSheetView: View {
    let beds: [AmbientBedRecord]
    let initialBedId: String?
    let attachedBedId: String?
    let isBaking: Bool
    var onSave: (AmbientBedSpec) async -> AmbientBedRecord?
    var onDelete: (String) -> Bool
    var onRename: (String, String) -> Void
    var onAttach: (AmbientBedRecord) -> Void
    var onClose: () -> Void

    @State private var spec = AmbientBedSpec().normalized()
    @State private var hzFieldText = ""
    @State private var preview = AmbientPreviewEngine()
    @State private var isPreviewing = false
    @State private var previewStatus = ""
    @State private var pendingDeleteBed: AmbientBedRecord?
    @State private var renamingBedId: String?
    @State private var renameText = ""

    /// Numeral subset of the detent stations — every detent gets a major
    /// tick, but engraving all 31 numbers would collide at this width.
    private static let rulerNumeralsHz: [Double] = [
        40, 55, 80, 110, 160, 220, 320, 432, 640, 880, 1_200, 1_600, 2_500, 4_000, 8_000
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                instrumentColumn
                    .frame(width: 640)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                Rectangle().fill(PlateColor.hairline).frame(width: 1)
                bedShelf
                    .frame(width: 286)
            }
            .frame(height: 540)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            footer
        }
        .frame(width: 960)
        .background(PlateColor.cream)
        .environment(\.colorScheme, .light)
        .background(keyboardControls)
        .onAppear {
            if let initialBedId, let record = beds.first(where: { $0.bedId == initialBedId }) {
                spec = record.spec.normalized()
            }
            hzFieldText = String(format: "%.2f", spec.tunerHz)
        }
        .onChange(of: spec) { oldValue, newValue in
            guard isPreviewing else { return }
            if oldValue.seed != newValue.seed || oldValue.durationSeconds != newValue.durationSeconds {
                // Seed and duration reshape the voicing and the drift-cycle
                // snapping — they need a fresh synth, not a smoothed glide.
                restartPreview()
            } else {
                preview.update(newValue.parameters)
            }
        }
        .onDisappear { stopPreview() }
        .confirmationDialog(
            "Move this ambient bed to Trash?",
            isPresented: Binding(
                get: { pendingDeleteBed != nil },
                set: { if !$0 { pendingDeleteBed = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move Bed to Trash", role: .destructive) {
                if let bed = pendingDeleteBed { _ = onDelete(bed.bedId) }
                pendingDeleteBed = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteBed = nil }
        } message: {
            Text("Shots using this bed lose their ambient lane.")
        }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack(spacing: 10) {
            PlateLabel(text: "AMBIENT BED TUNER", size: 11, weight: .bold)
            Rectangle().fill(PlateColor.hairline).frame(height: 1)
            PlateLabel(text: "SEAMLESS LOOP", size: 8.5, color: PlateColor.inkFaint)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close the tuner")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isBaking {
                ProgressView().controlSize(.small)
                PlateLabel(text: "BAKING…", size: 8.5, color: PlateColor.inkFaint)
            } else if !previewStatus.isEmpty {
                Text(previewStatus)
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(PlateColor.inkFaint)
                    .lineLimit(1)
            } else {
                Text("Bake renders \(Int(spec.durationSeconds)) s of seamlessly loopable bed — no provider, no spend.")
                    .font(.system(size: 10, design: .serif))
                    .foregroundStyle(PlateColor.inkFaint)
                    .lineLimit(1)
            }
            Spacer()
            Button("CANCEL", action: onClose)
                .buttonStyle(PlateButtonStyle())
                .keyboardShortcut(.cancelAction)
            Button("BAKE BED") { bake(attach: false) }
                .buttonStyle(PlateButtonStyle())
                .disabled(isBaking)
                .help("Bake this spec into the project's bed shelf")
            Button("BAKE & ATTACH") { bake(attach: true) }
                .buttonStyle(PlateButtonStyle(isProminent: true))
                .disabled(isBaking)
                .help("Bake, attach to this shot's AMBIENT lane, and close")
        }
        .padding(16)
    }

    // MARK: - Instrument column

    private var instrumentColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            readoutRow
            durationRow
            rulerCanvas
            widthRow
            HStack(alignment: .top, spacing: 26) {
                AmbientFilterDial(label: "WARMTH", value: $spec.warmth, defaultValue: 0.35)
                AmbientFilterDial(label: "DRIFT", value: $spec.drift, defaultValue: 0.25)
                AmbientFilterDial(label: "CRACKLE", value: $spec.crackle, defaultValue: 0.10)
                AmbientFilterDial(label: "WASH", value: $spec.wash, defaultValue: 0.30)
                Spacer()
            }
            transportRow
            Spacer(minLength: 0)
        }
    }

    private var readoutRow: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%07.2f", spec.tunerHz))
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .foregroundStyle(PlateColor.ink)
                PlateLabel(text: "HZ", size: 9, weight: .semibold, color: PlateColor.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .plateEngravedBorder(cornerRadius: 3, inset: 2)

            HStack(spacing: 4) {
                TextField("Hz", text: $hzFieldText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(PlateColor.ink)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .frame(width: 76)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(PlateColor.hairline, lineWidth: 1))
                    .onSubmit(commitHzField)
                Button("SET", action: commitHzField)
                    .buttonStyle(PlateButtonStyle())
                    .help("Tune to the typed frequency")
            }

            Spacer()

            Button("RESEED") {
                spec.seed = UInt64.random(in: 1...999_999)
            }
            .buttonStyle(PlateButtonStyle())
            .help("New noise voicing at the same settings")
            Text("SEED \(spec.seed)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(PlateColor.inkFaint)
        }
    }

    private var durationRow: some View {
        HStack(spacing: 8) {
            PlateLabel(text: "DURATION", size: 8, weight: .semibold, color: PlateColor.inkFaint)
            ForEach(AmbientTunerMetrics.durationChoicesSeconds, id: \.self) { choice in
                Button("\(Int(choice)) S") { spec.durationSeconds = choice }
                    .buttonStyle(PlateButtonStyle(isProminent: spec.durationSeconds == choice))
                    .help("Loop length: \(Int(choice)) seconds")
            }
            Spacer()
        }
    }

    private var rulerCanvas: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Canvas { context, size in
                drawRuler(context: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        // Live-modifier read is the house pattern for drags.
                        let shiftDown = NSEvent.modifierFlags.contains(.shift)
                        let fraction = Double(drag.location.x / max(width, 1))
                        setTunerHz(ambientTunerSnappedHz(
                            rawHz: ambientTunerHz(atRulerFraction: fraction),
                            shiftDown: shiftDown
                        ))
                    }
            )
        }
        .frame(height: 96)
        .plateEngravedBorder(cornerRadius: 3, inset: 2)
        .help("Drag to tune — hold Shift to jump between the engraved detents")
    }

    private var widthRow: some View {
        HStack(spacing: 8) {
            PlateLabel(text: "WIDTH", size: 8, weight: .semibold, color: PlateColor.inkFaint)
            Slider(
                value: Binding(
                    get: { ambientTunerWidthFraction(forBandwidthOctaves: spec.bandwidthOctaves) },
                    set: { spec.bandwidthOctaves = ambientTunerBandwidthOctaves(atWidthFraction: $0) }
                ),
                in: 0...1
            )
            .controlSize(.mini)
            .frame(width: 220)
            Text("\(Int((ambientTunerWidthFraction(forBandwidthOctaves: spec.bandwidthOctaves) * 100).rounded()))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(PlateColor.inkFaint)
            Text("narrow whistle ⟷ broad wash")
                .font(.system(size: 9, design: .serif))
                .italic()
                .foregroundStyle(PlateColor.inkFaint)
            Spacer()
        }
    }

    private var transportRow: some View {
        HStack(spacing: 12) {
            Button(isPreviewing ? "■ STOP" : "► AUDITION") { toggleAudition() }
                .buttonStyle(PlateButtonStyle(isProminent: isPreviewing))
                .help(isPreviewing ? "Stop the live preview" : "Audition the bed live — every control is audible immediately")
            PlateLabel(text: "LEVEL", size: 8, weight: .semibold, color: PlateColor.inkFaint)
            Slider(value: $spec.outputLevel, in: 0...1)
                .controlSize(.mini)
                .frame(width: 120)
            Text("the live preview follows every control")
                .font(.system(size: 9, design: .serif))
                .italic()
                .foregroundStyle(PlateColor.inkFaint)
            Spacer()
        }
    }

    // MARK: - Bed shelf

    private var bedShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                PlateLabel(text: "PROJECT BEDS (\(beds.count))", size: 8.5, weight: .semibold)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Rectangle().fill(PlateColor.hairlineFaint).frame(height: 1)
            if beds.isEmpty {
                Text("No beds yet — tune the instrument and bake the first.")
                    .font(.system(size: 10, design: .serif))
                    .italic()
                    .foregroundStyle(PlateColor.inkFaint)
                    .padding(14)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(beds) { bed in
                            shelfRow(bed)
                            Rectangle().fill(PlateColor.hairlineFaint).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func shelfRow(_ bed: AmbientBedRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if renamingBedId == bed.bedId {
                TextField("Bed name", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .serif))
                    .foregroundStyle(PlateColor.ink)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(PlateColor.hairline, lineWidth: 1))
                    .onSubmit {
                        onRename(bed.bedId, renameText)
                        renamingBedId = nil
                    }
            } else {
                HStack(spacing: 6) {
                    Text(bed.displayName)
                        .font(.system(size: 10.5, weight: .semibold, design: .serif))
                        .foregroundStyle(PlateColor.ink)
                        .lineLimit(1)
                    if bed.bedId == attachedBedId {
                        PlateLabel(text: "ON THIS SHOT", size: 6.5, weight: .semibold, color: PlateColor.inkFaint)
                    }
                }
            }
            HStack(spacing: 8) {
                Text("\(ambientShelfDuration(bed.durationSeconds)) · \(String(format: "%.2f", bed.spec.tunerHz)) Hz")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(PlateColor.inkFaint)
                Spacer()
                Button {
                    spec = bed.spec.normalized()
                    hzFieldText = String(format: "%.2f", spec.tunerHz)
                } label: {
                    PlateLabel(text: "LOAD", size: 7.5, weight: .semibold)
                }
                .buttonStyle(.plain)
                .help("Load this bed's settings into the tuner")
                Button {
                    renameText = bed.displayName
                    renamingBedId = bed.bedId
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(PlateColor.inkFaint)
                }
                .buttonStyle(.plain)
                .help("Rename this bed")
                Button {
                    pendingDeleteBed = bed
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(PlateColor.inkFaint)
                }
                .buttonStyle(.plain)
                .help("Move this bed to Trash and detach it from every shot")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Ruler drawing

    private func drawRuler(context: inout GraphicsContext, size: CGSize) {
        let width = size.width
        let baselineY: CGFloat = 56
        let ink = GraphicsContext.Shading.color(PlateColor.ink)
        let faint = GraphicsContext.Shading.color(PlateColor.inkFaint)
        let hairline = GraphicsContext.Shading.color(PlateColor.hairline)

        var baseline = Path()
        baseline.move(to: CGPoint(x: 0, y: baselineY))
        baseline.addLine(to: CGPoint(x: width, y: baselineY))
        context.stroke(baseline, with: hairline, lineWidth: 1)

        // Minor ticks: every 1/24 octave across the whole range.
        var minors = Path()
        var frequency = AmbientTunerMetrics.minHz
        while frequency <= AmbientTunerMetrics.maxHz * 1.000_001 {
            let x = ambientTunerRulerFraction(forHz: frequency) * width
            minors.move(to: CGPoint(x: x, y: baselineY))
            minors.addLine(to: CGPoint(x: x, y: baselineY - 8))
            frequency *= pow(2, 1.0 / 24.0)
        }
        context.stroke(minors, with: hairline, lineWidth: 0.6)

        // Major ticks at every detent station; numerals on the curated subset.
        var majors = Path()
        for detent in AmbientTunerMetrics.detentsHz {
            let x = ambientTunerRulerFraction(forHz: detent) * width
            majors.move(to: CGPoint(x: x, y: baselineY))
            majors.addLine(to: CGPoint(x: x, y: baselineY - 17))
            if Self.rulerNumeralsHz.contains(detent) {
                var numeral = context.resolve(
                    Text(ambientRulerNumeral(detent)).font(PlateType.label(6.5))
                )
                numeral.shading = faint
                context.draw(numeral, at: CGPoint(x: x, y: baselineY + 12))
            }
        }
        context.stroke(majors, with: faint, lineWidth: 1)

        // The needle at the tuned frequency, pointer riding above.
        let needleX = ambientTunerRulerFraction(forHz: spec.tunerHz) * width
        var needle = Path()
        needle.move(to: CGPoint(x: needleX, y: 10))
        needle.addLine(to: CGPoint(x: needleX, y: baselineY + 4))
        context.stroke(needle, with: ink, lineWidth: 1.4)
        let pointerRect = CGRect(x: needleX - 5, y: 2, width: 10, height: 9)
        // PlatePointer points -x within its rect; rotate to point down.
        var pointer = PlatePointer().path(in: CGRect(origin: .zero, size: pointerRect.size))
        pointer = pointer.applying(
            CGAffineTransform(translationX: -pointerRect.width / 2, y: -pointerRect.height / 2)
                .concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
                .concatenating(CGAffineTransform(translationX: pointerRect.midX, y: pointerRect.midY))
        )
        context.fill(pointer, with: ink)
    }

    private func ambientRulerNumeral(_ hz: Double) -> String {
        hz >= 1_000 ? String(format: "%.1fk", hz / 1_000) : String(Int(hz))
    }

    private func ambientShelfDuration(_ seconds: Double) -> String {
        let whole = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // MARK: - Keyboard

    private var keyboardControls: some View {
        Group {
            Button("") { stepTuner(1, AmbientTunerMetrics.stepPlainHz) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("") { stepTuner(-1, AmbientTunerMetrics.stepPlainHz) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { stepTuner(1, AmbientTunerMetrics.stepFineHz) }
                .keyboardShortcut(.rightArrow, modifiers: [.option])
            Button("") { stepTuner(-1, AmbientTunerMetrics.stepFineHz) }
                .keyboardShortcut(.leftArrow, modifiers: [.option])
            Button("") { stepTuner(1, AmbientTunerMetrics.stepHairHz) }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .shift])
            Button("") { stepTuner(-1, AmbientTunerMetrics.stepHairHz) }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .shift])
            Button("") { setTunerHz(ambientTunerNextDetentHz(fromHz: spec.tunerHz, direction: 1)) }
                .keyboardShortcut(.rightArrow, modifiers: [.shift])
            Button("") { setTunerHz(ambientTunerNextDetentHz(fromHz: spec.tunerHz, direction: -1)) }
                .keyboardShortcut(.leftArrow, modifiers: [.shift])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: - Actions

    private func setTunerHz(_ hz: Double) {
        spec.tunerHz = hz
        hzFieldText = String(format: "%.2f", hz)
    }

    private func stepTuner(_ direction: Int, _ stepHz: Double) {
        setTunerHz(ambientTunerSteppedHz(fromHz: spec.tunerHz, direction: direction, stepHz: stepHz))
    }

    private func commitHzField() {
        guard let typed = Double(hzFieldText.trimmed) else {
            hzFieldText = String(format: "%.2f", spec.tunerHz)
            return
        }
        setTunerHz(ambientTunerSnappedHz(rawHz: typed, shiftDown: false))
    }

    private func toggleAudition() {
        if isPreviewing {
            stopPreview()
        } else {
            do {
                try preview.start(spec: spec)
                isPreviewing = true
                previewStatus = ""
            } catch {
                previewStatus = error.localizedDescription
            }
        }
    }

    private func restartPreview() {
        preview.stop()
        do {
            try preview.start(spec: spec)
        } catch {
            isPreviewing = false
            previewStatus = error.localizedDescription
        }
    }

    private func stopPreview() {
        preview.stop()
        isPreviewing = false
    }

    private func bake(attach: Bool) {
        stopPreview()
        let baked = spec
        Task {
            guard let record = await onSave(baked) else { return }
            if attach {
                onAttach(record)
                onClose()
            }
        }
    }
}

/// 72pt engraved filter dial: tick ring, ink needle sweeping −135°…+135° over
/// 0…1, vertical drag to adjust, double-click to reset.
private struct AmbientFilterDial: View {
    let label: String
    @Binding var value: Double
    let defaultValue: Double

    @State private var dragStartValue: Double?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(PlateColor.hairline, lineWidth: 1)
                PlateTickRing(tickCount: 28, majorEvery: 7, minorLength: 3, majorLength: 6)
                    .stroke(PlateColor.inkFaint, lineWidth: 0.8)
                    .padding(4)
                Capsule()
                    .fill(PlateColor.ink)
                    .frame(width: 2, height: 24)
                    .offset(y: -13)
                    .rotationEffect(.degrees(-135 + value * 270))
                Circle()
                    .fill(PlateColor.ink)
                    .frame(width: 5, height: 5)
            }
            .frame(width: 72, height: 72)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragStartValue == nil { dragStartValue = value }
                        let delta = -Double(drag.translation.height) / 200
                        value = min(max((dragStartValue ?? value) + delta, 0), 1)
                    }
                    .onEnded { _ in dragStartValue = nil }
            )
            .onTapGesture(count: 2) { value = defaultValue }
            .help("Drag vertically to adjust — double-click resets")
            PlateLabel(text: label, size: 7.5, weight: .semibold)
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(PlateColor.inkFaint)
        }
    }
}
