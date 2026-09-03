import AppKit
import SwiftUI

/// Contextual edit-point inspector for one nondestructive razor range. The
/// first interaction is always review: exact boundary frames, executable
/// provider capability, native duration, prompt, and paid/free distinction.
struct ShotJoinRepairPopover: View {
    let shot: ProjectShot
    let cut: ShotSegmentCutRange
    let effectiveDissolveFrames: Int
    let hasFALCredential: Bool
    let isRendering: Bool
    let isRenderBlocked: Bool
    var onSetRepair: (ShotRazorJoinRepair) -> Void
    var onRestoreCut: () -> Void
    var onRenderBridge: (ShotJoinBridgeProvider, Int, String) -> Void
    var onPrepareBoundaryFrames: () async -> ShotJoinBoundaryPreview?
    /// TIMING: the cut's edges as typed material timecodes and per-edge frame
    /// nudges — the numeric parity the drag razor never had. nil (legacy
    /// hosts) hides the section.
    var assembly: ShotCutAssembly? = nil
    var onSetCutRange: ((_ materialStart: Double, _ materialEnd: Double) -> Void)? = nil

    @State private var selectedProvider: ShotJoinBridgeProvider = .falViduQ3
    @State private var selectedDuration = 2
    @State private var prompt = ShotJoinBridgePrompt.defaultText
    @State private var boundaryPreview: ShotJoinBoundaryPreview?
    @State private var isPreparingFrames = false

    private var versions: [ShotJoinBridgeArtifact] {
        shot.joinBridgeVersions
            .filter { $0.cutId == cut.id }
            .sorted { lhs, rhs in lhs.generatedAt > rhs.generatedAt }
    }

    private var activeArtifact: ShotJoinBridgeArtifact? {
        shot.joinBridgeVersion(cut.joinRepair.activeBridgeVersionId)
    }

    private var activeBridgeIsMissing: Bool {
        guard cut.joinRepair.mode == .generatedBridge else { return false }
        guard let activeArtifact, activeArtifact.isReady else { return true }
        return !FileManager.default.fileExists(atPath: activeArtifact.videoPath)
    }

    /// The cut's span in the strip's material space — typed timecodes and
    /// ±1F/±10F nudges per edge. Every commit is one cut-list write through
    /// the same clamp law as the drag, and re-assembles free.
    private func timingSection(
        range: ClosedRange<Double>,
        onSetCutRange: @escaping (Double, Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PlateLabel(text: "TIMING", size: 8, weight: .bold, color: PlateColor.ink)
            PlateLabel(
                text: "Material seconds — the strip's own space. Edges clamp inside this segment; free, never a render.",
                size: 7.5,
                color: PlateColor.inkFaint
            )
            HStack(spacing: 12) {
                edgeControls(
                    label: "START",
                    seconds: range.lowerBound,
                    onCommit: { onSetCutRange($0, range.upperBound) }
                )
                edgeControls(
                    label: "END",
                    seconds: range.upperBound,
                    onCommit: { onSetCutRange(range.lowerBound, $0) }
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func edgeControls(
        label: String,
        seconds: Double,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            ShotTimecodeField(
                label: label,
                seconds: seconds,
                isEnabled: true,
                onCommit: onCommit
            )
            Button {
                let frames = NSEvent.modifierFlags.contains(.shift) ? 10.0 : 1.0
                onCommit(seconds - frames * ShotAudioTiming.frameSeconds)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("\(label) one frame earlier (Shift: 10)")
            Button {
                let frames = NSEvent.modifierFlags.contains(.shift) ? 10.0 : 1.0
                onCommit(seconds + frames * ShotAudioTiming.frameSeconds)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
            }
            .buttonStyle(.plain)
            .help("\(label) one frame later (Shift: 10)")
        }
    }

    /// The carrier behind a SPEED SECTION razor, when this razor is one. Its
    /// material isn't removed — it plays through the linked ⟳ copy at another
    /// rate — so joins, TIMING, and bridges don't apply here.
    private var carrierInsertion: ShotPictureInsertion? {
        shot.pictureInsertions.first { $0.replacesRazorCutIds.contains(cut.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                boundaryFrames
                if let carrier = carrierInsertion {
                    Rectangle().fill(PlateColor.hairline).frame(height: 1)
                    carrierNote(carrier)
                } else {
                    if let assembly,
                       let onSetCutRange,
                       let range = shotRazorCutMaterialRange(cut: cut, assembly: assembly) {
                        Rectangle().fill(PlateColor.hairline).frame(height: 1)
                        timingSection(range: range, onSetCutRange: onSetCutRange)
                    }
                    Rectangle().fill(PlateColor.hairline).frame(height: 1)
                    localRepair
                    Rectangle().fill(PlateColor.hairline).frame(height: 1)
                    generatedRepair
                    if !versions.isEmpty {
                        Rectangle().fill(PlateColor.hairline).frame(height: 1)
                        versionHistory
                    }
                }
                Rectangle().fill(PlateColor.hairline).frame(height: 1)
                restoreAction
            }
            .padding(16)
        }
        .frame(width: 430, height: carrierInsertion == nil ? 680 : 430)
        .background(PlateColor.cream)
        .task(id: cut.id) {
            isPreparingFrames = true
            boundaryPreview = await onPrepareBoundaryFrames()
            isPreparingFrames = false
        }
        .onChange(of: selectedProvider) { _, provider in
            selectedDuration = provider.defaultDuration
        }
    }

    /// The one honest paragraph a speed-carrier razor shows in place of the
    /// join machinery, plus where its controls actually live.
    private func carrierNote(_ carrier: ShotPictureInsertion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PlateLabel(text: "SPEED SECTION", size: 8, weight: .bold, color: PlateColor.ink)
            PlateLabel(
                text: "This razor carries a speed section — the \(String(format: "%.2f", cut.seconds))s it hides "
                    + "plays through the linked ⟳ copy at \(shotInsertionRateLabel(carrier.playbackRate)). "
                    + "Joins, TIMING, and bridges don't apply: moving the bite would desync the copy.",
                size: 7.5,
                color: PlateColor.inkFaint
            )
            PlateLabel(
                text: "Speed, sound, and delete live on the ⟳ cell. RESTORE below returns the material at 1× — the copy goes with it.",
                size: 7.5,
                color: PlateColor.inkFaint
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                PlateLabel(
                    text: carrierInsertion == nil ? "REPAIR JOIN" : "SPEED SECTION RAZOR",
                    size: 11,
                    weight: .bold,
                    color: PlateColor.ink
                )
                PlateLabel(
                    text: carrierInsertion == nil
                        ? "RAZOR CUT · \(String(format: "%.2f", cut.seconds))S REMOVED"
                        : "CARRIES \(String(format: "%.2f", cut.seconds))S AT \(shotInsertionRateLabel(carrierInsertion?.playbackRate ?? 1))",
                    size: 7.5,
                    color: PlateColor.inkFaint
                )
            }
            Spacer()
            PlateLabel(text: currentStateLabel, size: 8, weight: .semibold, color: PlateColor.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(PlateColor.creamDeep)
                .overlay(Rectangle().stroke(PlateColor.ink, lineWidth: 1))
        }
    }

    private var currentStateLabel: String {
        switch cut.joinRepair.mode {
        case .hardCut: return "HARD CUT"
        case .dissolve:
            return effectiveDissolveFrames == cut.joinRepair.dissolveFrames
                ? "DISSOLVE · \(effectiveDissolveFrames)F"
                : "DISSOLVE · \(effectiveDissolveFrames)/\(cut.joinRepair.dissolveFrames)F"
        case .generatedBridge:
            return activeBridgeIsMissing
                ? "AI BRIDGE · MISSING"
                : "AI BRIDGE · \(String(format: "%.2f", activeArtifact?.durationSeconds ?? 0))S"
        }
    }

    private var boundaryFrames: some View {
        VStack(alignment: .leading, spacing: 7) {
            PlateLabel(text: "EXACT EDIT BOUNDARIES", size: 7.5, weight: .semibold, color: PlateColor.inkFaint)
            // The labels name PLAY order, so on a reversed cut the frame you
            // leave the join on is the one the forward edit called incoming.
            // The cut itself is untouched — it is defined in forward file
            // seconds and the bridge is rendered from the same pair either way.
            HStack(spacing: 8) {
                boundaryCard(
                    label: "OUT",
                    url: shot.cutList.isReversed ? boundaryPreview?.incomingURL : boundaryPreview?.outgoingURL
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PlateColor.inkFaint)
                boundaryCard(
                    label: "IN",
                    url: shot.cutList.isReversed ? boundaryPreview?.outgoingURL : boundaryPreview?.incomingURL
                )
            }
            if boundaryPreview == nil, !isPreparingFrames {
                PlateLabel(
                    text: "BOUNDARY FRAMES UNAVAILABLE — THE SOURCE TAKE MAY HAVE MOVED",
                    size: 7,
                    color: CanonColor.brass
                )
            }
        }
    }

    private func boundaryCard(label: String, url: URL?) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.black.opacity(0.9))
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isPreparingFrames {
                ProgressView().controlSize(.small).tint(PlateColor.cream)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(PlateColor.cream.opacity(0.55))
            }
            PlateLabel(text: label, size: 7.5, weight: .bold, color: PlateColor.cream)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(PlateColor.ink.opacity(0.72))
        }
        .frame(height: 106)
        .clipped()
        .overlay(Rectangle().stroke(PlateColor.ink, lineWidth: 1))
    }

    private var localRepair: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PlateLabel(text: "LOCAL REPAIR", size: 8.5, weight: .bold, color: PlateColor.ink)
                Spacer()
                PlateLabel(text: "FREE · VIDEO ONLY", size: 7, color: PlateColor.inkFaint)
            }
            HStack(spacing: 7) {
                Button("HARD CUT") {
                    onSetRepair(ShotRazorJoinRepair(mode: .hardCut))
                }
                .buttonStyle(PlateButtonStyle(isProminent: cut.joinRepair.mode == .hardCut))
                ForEach([6, 12, 24], id: \.self) { frames in
                    Button("\(frames)F") {
                        onSetRepair(ShotRazorJoinRepair(mode: .dissolve, dissolveFrames: frames))
                    }
                    .buttonStyle(PlateButtonStyle(
                        isProminent: cut.joinRepair.mode == .dissolve
                            && cut.joinRepair.dissolveFrames == frames
                    ))
                }
            }
            PlateLabel(
                text: "Dissolve borrows hidden handles around this edit. If fewer frames exist, it is capped rather than freezing frames.",
                size: 7.5,
                color: PlateColor.inkFaint
            )
            if cut.joinRepair.mode == .dissolve,
               effectiveDissolveFrames < cut.joinRepair.dissolveFrames {
                PlateLabel(
                    text: "INSUFFICIENT HANDLES · REQUESTED \(cut.joinRepair.dissolveFrames)F, PLAYING \(effectiveDissolveFrames)F",
                    size: 7,
                    color: CanonColor.brass
                )
            }
        }
    }

    private var generatedRepair: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                PlateLabel(text: "AI BRIDGE", size: 8.5, weight: .bold, color: PlateColor.ink)
                Spacer()
                PlateLabel(text: "PAID RENDER · INSERT + RIPPLE", size: 7, color: CanonColor.brass)
            }
            HStack(spacing: 7) {
                ForEach(ShotJoinBridgeProvider.allCases, id: \.rawValue) { provider in
                    Button(provider == .falViduQ3 ? "VIDU Q3" : "KLING O1") {
                        selectedProvider = provider
                    }
                    .buttonStyle(PlateButtonStyle(isProminent: selectedProvider == provider))
                    .disabled(!hasFALCredential)
                    .help(hasFALCredential ? provider.label : "Add a FAL API key in App Settings")
                }
                Spacer()
                ForEach(selectedProvider.supportedDurations, id: \.self) { seconds in
                    Button("\(seconds)S") { selectedDuration = seconds }
                        .buttonStyle(PlateButtonStyle(isProminent: selectedDuration == seconds))
                }
            }
            TextEditor(text: $prompt)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(PlateColor.ink)
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 108)
                .background(PlateColor.creamDeep.opacity(0.35))
                .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
            HStack {
                PlateLabel(
                    text: hasFALCredential
                        ? "\(selectedProvider.label) · \(selectedDuration)S · 1080P · NATIVE RATE"
                        : "LOCKED · ADD FAL API KEY IN APP SETTINGS",
                    size: 7,
                    color: hasFALCredential ? PlateColor.inkFaint : CanonColor.brass
                )
                Spacer()
                Button(isRendering ? "RENDERING…" : "RENDER \(selectedDuration)S BRIDGE") {
                    onRenderBridge(selectedProvider, selectedDuration, prompt)
                }
                .buttonStyle(PlateButtonStyle(isProminent: true))
                .disabled(
                    isRendering
                        || isRenderBlocked
                        || !hasFALCredential
                        || boundaryPreview == nil
                        || prompt.trimmed.isEmpty
                )
            }
            if activeBridgeIsMissing {
                PlateLabel(
                    text: "THE SELECTED BRIDGE FILE IS MISSING. PLAYBACK FALLS BACK TO THE HARD CUT; REGENERATE OR CHOOSE ANOTHER VERSION.",
                    size: 7,
                    color: CanonColor.brass
                )
            }
        }
    }

    private var versionHistory: some View {
        VStack(alignment: .leading, spacing: 7) {
            PlateLabel(text: "BRIDGE VERSIONS", size: 8.5, weight: .bold, color: PlateColor.ink)
            ForEach(versions.prefix(4)) { version in
                HStack(spacing: 8) {
                    Circle()
                        .fill(version.status == "ready" ? CanonColor.brass : PlateColor.inkFaint)
                        .frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 2) {
                        PlateLabel(
                            text: "\(ShotJoinBridgeProvider(rawValue: version.provider)?.label ?? version.provider.uppercased()) · \(String(format: "%.2f", version.durationSeconds))S · \(version.status.uppercased())",
                            size: 7.5,
                            weight: .semibold,
                            color: PlateColor.ink
                        )
                        if !version.errorMessage.isEmpty {
                            Text(version.errorMessage)
                                .font(.system(size: 9))
                                .foregroundStyle(CanonColor.brass)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    if version.isReady, FileManager.default.fileExists(atPath: version.videoPath) {
                        Button("USE") {
                            onSetRepair(ShotRazorJoinRepair(
                                mode: .generatedBridge,
                                activeBridgeVersionId: version.versionId
                            ))
                        }
                        .buttonStyle(PlateButtonStyle(
                            isProminent: cut.joinRepair.activeBridgeVersionId == version.versionId
                        ))
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([
                                URL(fileURLWithPath: version.videoPath)
                            ])
                        } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain)
                        .help("Reveal this bridge in Finder")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var restoreAction: some View {
        // THE RAZOR BLOCK LAW: overlapping/abutting cuts restore together —
        // the copy states the block so "restore" and "what comes back" agree.
        let block = shotRazorCutIdsInSameBlock(cutList: shot.cutList, cutId: cut.id)
        let blockSeconds = shot.cutList.segmentCuts
            .filter { block.contains($0.id) }
            .reduce(0) { $0 + $1.seconds }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                PlateLabel(text: "RESTORE CUT MATERIAL", size: 8, weight: .bold, color: PlateColor.ink)
                PlateLabel(
                    text: block.count > 1
                        ? "Returns this whole razor block — \(block.count) cuts, ~\(String(format: "%.2f", blockSeconds))s; bridge history remains in provenance."
                        : "Returns the removed \(String(format: "%.2f", cut.seconds))s; bridge history remains in provenance.",
                    size: 7,
                    color: PlateColor.inkFaint
                )
            }
            Spacer()
            Button(block.count > 1 ? "RESTORE ×\(block.count)" : "RESTORE") { onRestoreCut() }
                .buttonStyle(PlateButtonStyle())
        }
    }
}
