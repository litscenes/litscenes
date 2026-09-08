import SwiftUI

/// The compact paid confirmation reached from the Scene tail or NEW TAKE.
/// It owns only ephemeral review state; dismissing it cannot add a marker,
/// select a take, or write a prompt override.
struct ShotContinuationReviewView: View {
    let availability: ShotContinuationAvailability
    let configuredModels: Set<ShotRenderModel>
    let pricing: FALPricingSnapshot?
    let title: String
    var onCancel: () -> Void
    var onRender: (ShotContinuationRequest) -> Void

    @State private var mode: ShotContinuationMode
    @State private var stack: ShotRenderStack
    @State private var prompt: String

    init(
        availability: ShotContinuationAvailability,
        configuredModels: Set<ShotRenderModel>,
        pricing: FALPricingSnapshot?,
        title: String,
        onCancel: @escaping () -> Void,
        onRender: @escaping (ShotContinuationRequest) -> Void
    ) {
        self.availability = availability
        self.configuredModels = configuredModels
        self.pricing = pricing
        self.title = title
        self.onCancel = onCancel
        self.onRender = onRender
        let initialMode = availability.preferredMode
        _mode = State(initialValue: initialMode)
        _stack = State(initialValue: initialMode == .nativeExtend
            ? (availability.nativeStack ?? availability.outFrameStack)
            : availability.outFrameStack)
        _prompt = State(initialValue: availability.suggestedPrompt)
    }

    private var executableOutFrameModels: [ShotRenderModel] {
        ShotRenderModel.shotDefaultCases.filter {
            configuredModels.contains($0) && $0 != .falLTX23Narration
                && (availability.targetFrame == nil || $0.supportsShotEnding)
        }
    }

    private var price: Double? {
        guard let anchor = availability.anchor else { return nil }
        if mode == .nativeExtend {
            guard let context = ltxShotExtendContextSeconds(
                sourceDurationSeconds: anchor.tailClipDurationSeconds,
                extensionDurationSeconds: stack.segmentSeconds
            ) else { return nil }
            return ShotRenderCostEstimate.nativeExtendUSD(
                durationSeconds: stack.segmentSeconds,
                contextSeconds: context
            )
        }
        return ShotRenderCostEstimate.segmentUSD(stack: stack, pricing: pricing)
    }

    private var priceLabel: String {
        guard let price else { return "RATE UNAVAILABLE" }
        return price > 0 && price < 0.01
            ? String(format: "EST. $%.3f", price)
            : String(format: "EST. $%.2f", price)
    }

    private var canSubmit: Bool {
        !prompt.trimmed.isEmpty
            && availability.anchor != nil
            && price != nil
            && configuredModels.contains(stack.model)
            && (availability.targetFrame == nil || stack.model.supportsShotEnding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title.uppercased())
                    .font(CanonType.archive(9, weight: .bold))
                    .kerning(1.2)
                Spacer()
                Text("PAID VIDEO GENERATION")
                    .font(CanonType.archive(7, weight: .semibold))
                    .kerning(0.7)
                    .foregroundStyle(CanonColor.ink.opacity(0.65))
            }

            endpointPreview

            if let target = availability.targetFrame {
                HStack(spacing: 10) {
                    Group {
                        if let image = StripThumbnailCache.shared.image(path: target.imagePath) {
                            Image(nsImage: image).resizable().scaledToFit()
                        } else { Image(systemName: "photo") }
                    }
                    .frame(width: 160, height: 90)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ENDING FRAME").font(CanonType.archive(8, weight: .bold))
                        Text(target.label).font(CanonType.interface(11))
                        Text("Arrive at this Frame using a paired-frame model.").font(CanonType.interface(10))
                    }
                }
            } else {
            Text("CONTINUATION METHOD")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(CanonColor.ink.opacity(0.65))
            HStack(spacing: 8) {
                methodButton(
                    mode: .nativeExtend,
                    title: "NATIVE EXTEND",
                    detail: availability.nativeStack == nil
                        ? "Needs a video tail of at least 3s and an LTX key"
                        : "Carries motion and source audio continuity"
                )
                methodButton(
                    mode: .outFrame,
                    title: "OUT-FRAME",
                    detail: availability.outFrameAvailable
                        ? "Starts a new clip from the exact final frame"
                        : "No image-to-video provider is configured"
                )
            }

            }
            if mode != .nativeExtend {
                outFrameControls
            } else if let context = availability.anchor.flatMap({ anchor in
                ltxShotExtendContextSeconds(
                    sourceDurationSeconds: anchor.tailClipDurationSeconds,
                    extensionDurationSeconds: stack.segmentSeconds
                )
            }) {
                Text("\(stack.providerSelection.label) · LTX 2.3 · \(stack.segmentSeconds)s new · \(String(format: "%.1f", context))s tail context · native audio")
                    .font(CanonType.archive(7.5, weight: .medium))
                    .foregroundStyle(CanonColor.ink.opacity(0.65))
            }

            Text("DIRECTION")
                .font(CanonType.archive(7.5, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(CanonColor.ink.opacity(0.65))
            TextEditor(text: $prompt)
                .font(CanonType.interface(12))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(height: 92)
                .background(Color.white.opacity(0.56), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper, lineWidth: 1))

            HStack(spacing: 8) {
                Button("CANCEL") { onCancel() }
                    .buttonStyle(PlateButtonStyle())
                Spacer()
                Button {
                    guard let anchor = availability.anchor else { return }
                    onRender(ShotContinuationRequest(
                        mode: mode,
                        stack: stack,
                        prompt: prompt,
                        preparedAnchor: anchor, targetFrame: availability.targetFrame
                    ))
                } label: {
                    Text("▶ RENDER TAKE · \(priceLabel)")
                        .font(CanonType.archive(8, weight: .bold))
                        .kerning(0.6)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .foregroundStyle(CanonColor.ink)
                        .background(Capsule().fill(CanonColor.brass.opacity(0.86)))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .help(price == nil
                    ? "Wait for a complete provider-rate estimate before rendering"
                    : "Generate one new immutable continuation take. This is the only action in this review that can spend.")
            }
        }
        .padding(16)
        .frame(width: 560)
        .background(CanonColor.paper)
        .foregroundStyle(CanonColor.ink)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
    }

    private var endpointPreview: some View {
        HStack(spacing: 12) {
            ZStack {
                CanonColor.mediaCardHover
                if let path = availability.anchor?.framePath,
                   let image = StripThumbnailCache.shared.image(path: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(CanonColor.ink.opacity(0.65))
                }
            }
            .frame(width: 176, height: 99)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper, lineWidth: 1))
            VStack(alignment: .leading, spacing: 5) {
                Text("EXACT CONTINUATION ANCHOR")
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(0.7)
                Text(anchorSourceLabel)
                    .font(CanonType.interface(11, weight: .semibold))
                Text(anchorSourceDetail)
                    .font(CanonType.interface(9.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
                if let notice = availability.endpointNotice {
                    Text(notice)
                        .font(CanonType.interface(9.5))
                        .foregroundStyle(CanonColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var anchorSourceLabel: String {
        switch availability.anchor?.sourceKind {
        case "frame": return "Ready Frame"
        case "footage": return "Placed Footage out point"
        case "continuation_take": return "Source continuation final frame"
        case "rendered_original": return "Rendered Original final frame"
        default: return "Saved Scene endpoint"
        }
    }

    private var anchorSourceDetail: String {
        if availability.anchor?.sourceKind == "frame" {
            return "This exact ready Frame is preserved with the take."
        }
        return "This still is extracted from the end of the source video and preserved with the take."
    }

    private func methodButton(
        mode candidate: ShotContinuationMode,
        title: String,
        detail: String
    ) -> some View {
        let available = candidate == .nativeExtend
            ? availability.nativeStack != nil
            : availability.outFrameAvailable
        return Button {
            guard available else { return }
            mode = candidate
            stack = candidate == .nativeExtend
                ? (availability.nativeStack ?? stack)
                : availability.outFrameStack
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: mode == candidate ? "largecircle.fill.circle" : "circle")
                    Text(title)
                        .font(CanonType.archive(8, weight: .bold))
                        .kerning(0.6)
                }
                Text(detail)
                    .font(CanonType.interface(8.5))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(CanonColor.ink.opacity(0.65))
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(mode == candidate ? CanonColor.softGold.opacity(0.3) : Color.white.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(mode == candidate ? CanonColor.brass : CanonColor.hairlinePaper, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
    }

    private var outFrameControls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(executableOutFrameModels) { model in
                    Menu(model.label) {
                        ForEach(model.supportedDurations, id: \.self) { seconds in
                            Button("\(seconds)s") {
                                stack = stack.replacingModel(model).replacingDuration(seconds)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("\(stack.providerSelection.label) · \(stack.shortLabel)")
                        .font(CanonType.archive(8, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.5)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CanonColor.hairlinePaper))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            if stack.model.supportsGeneratedAudio {
                Toggle("Native audio", isOn: Binding(
                    get: { stack.generateAudio },
                    set: { stack = stack.replacingGeneratedAudio($0) }
                ))
                .toggleStyle(.checkbox)
                .font(CanonType.interface(9.5))
            }
            Spacer()
        }
    }
}

/// A marker-scoped browser. Preview is local and free; Use is the only
/// selection mutation, and a branch that would stale downstream links names
/// those links before offering the separately priced rechain operation.
struct ShotContinuationTakeBrowserView: View {
    let record: ShotContinuationRecord
    let selectedEntryIsStale: Bool
    let rechainEntryIds: [String]
    let isRendering: Bool
    var allowsNewTake = true
    var rechainEstimate: ([String]) -> ShotRenderCostEstimate
    var branchImpact: (String) -> ShotContinuationBranchImpact?
    var onUse: (ShotContinuationBranchImpact) -> Void
    var onUseAndRechain: (ShotContinuationBranchImpact) -> Void
    var onRechain: () -> Void
    var onRepair: ((String) -> Void)? = nil
    var onNewTake: () -> Void
    var onClose: () -> Void

    @State private var previewTakeId = ""
    @State private var timestampSeconds = 0.0
    @State private var isPlaying = false
    @State private var pendingImpact: ShotContinuationBranchImpact?

    private var previewTake: ShotContinuationTake? {
        record.takes.first { $0.takeId == previewTakeId && $0.isReady }
            ?? record.selectedTake
            ?? record.readyTakes.last
    }

    private var hasStaleSelectedTake: Bool {
        selectedEntryIsStale && record.selectedTake != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("CONTINUATION TAKES")
                    .font(CanonType.archive(9, weight: .bold))
                    .kerning(1)
                Text("\(record.takes.count) retained")
                    .font(CanonType.archive(7.5, weight: .medium))
                    .foregroundStyle(CanonColor.muted)
                if hasStaleSelectedTake {
                    Text("STALE ANCHOR")
                        .font(CanonType.archive(7, weight: .bold))
                        .foregroundStyle(CanonColor.rust)
                }
                Spacer()
                Button("CLOSE") { onClose() }
                    .buttonStyle(PlateButtonStyle())
            }

            if let take = previewTake, let clip = take.segmentClip {
                ZStack {
                    Color.black
                    ScrubVideoPreview(
                        path: clip.clipPath,
                        timestampSeconds: $timestampSeconds,
                        isFreePlaying: isPlaying,
                        onPlaybackTime: { timestampSeconds = $0 },
                        onPlaybackEnded: { isPlaying = false }
                    )
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(width: 580)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                HStack(spacing: 8) {
                    Button(isPlaying ? "PAUSE" : "PLAY") { isPlaying.toggle() }
                        .buttonStyle(PlateButtonStyle())
                    Text("TAKE \(take.takeNumber) · \(take.renderStack.shortLabel)")
                        .font(CanonType.archive(7.5, weight: .semibold))
                        .foregroundStyle(CanonColor.muted)
                    Spacer()
                }
            }

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(record.sortedTakes.reversed())) { take in
                        takeRow(take)
                    }
                }
            }
            .frame(maxHeight: 220)

            HStack {
                if allowsNewTake {
                    Button(record.readyTakes.isEmpty ? "RETRY · REVIEW PRICE" : "RENDER NEW TAKE…") { onNewTake() }
                        .buttonStyle(PlateButtonStyle())
                        .disabled(isRendering || record.takes.isEmpty)
                        .help("Review the saved endpoint and current price for another immutable take")
                }
                Spacer()
                if hasStaleSelectedTake {
                    let estimate = rechainEstimate(rechainEntryIds)
                    Button("RECHAIN · \(estimate.headlineLabel ?? "RATE UNAVAILABLE")") {
                        onRechain()
                    }
                    .buttonStyle(PlateButtonStyle(isProminent: true))
                    .disabled(isRendering || rechainEntryIds.isEmpty || !estimate.isComplete)
                    .help(estimate.isComplete
                        ? "Generate only the stale links in order. Each completed take is retained, so a later failure can resume."
                        : "A complete estimate is required before rechain can submit paid work")
                }
            }
        }
        .padding(16)
        .frame(width: 620, height: 520)
        .background(CanonColor.paper)
        .confirmationDialog(
            impactTitle,
            isPresented: Binding(
                get: { pendingImpact != nil },
                set: { if !$0 { pendingImpact = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let impact = pendingImpact {
                switch impact.resolution {
                case .selectCurrent:
                    Button("Use Take · $0") {
                        onUse(impact)
                        pendingImpact = nil
                    }
                case .rechain(let staleEntryIds):
                    let estimate = rechainEstimate(staleEntryIds)
                    Button("Use Take · Keep Later Clips") {
                        onUse(impact)
                        pendingImpact = nil
                    }
                    Button("Use & Rechain · \(estimate.headlineLabel ?? "RATE UNAVAILABLE")") {
                        onUseAndRechain(impact)
                        pendingImpact = nil
                    }
                    .disabled(isRendering || !estimate.isComplete)
                }
                Button("Cancel", role: .cancel) { pendingImpact = nil }
            }
        } message: {
            Text(impactMessage)
        }
    }

    private func takeRow(_ take: ShotContinuationTake) -> some View {
        let selected = take.takeId == record.selectedTakeId
        let previewed = take.takeId == previewTake?.takeId
        return HStack(spacing: 9) {
            ZStack {
                CanonColor.mediaCardHover
                if let image = StripThumbnailCache.shared.image(path: take.finalFramePath) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else if [.queued, .generating].contains(take.takeStatus) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: take.takeStatus == .failed ? "exclamationmark.triangle" : "film")
                        .foregroundStyle(take.takeStatus == .failed ? CanonColor.rust : CanonColor.muted)
                }
            }
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("TAKE \(take.takeNumber)")
                        .font(CanonType.archive(8, weight: .bold))
                    Text(take.takeStatus.rawValue.uppercased())
                        .font(CanonType.archive(7, weight: .semibold))
                        .foregroundStyle(take.takeStatus == .failed ? CanonColor.rust : CanonColor.muted)
                    if selected {
                        Text("IN USE")
                            .font(CanonType.archive(7, weight: .bold))
                            .foregroundStyle(CanonColor.brass)
                    }
                }
                if !take.errorMessage.isEmpty {
                    Text(take.errorMessage).font(CanonType.interface(9)).foregroundStyle(CanonColor.rust)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !take.isReady, !take.requestId.isEmpty || take.workflowStep == "provider" {
                    Text("Provider acceptance may be unknown. A new take may charge again.")
                        .font(CanonType.interface(9)).foregroundStyle(CanonColor.rust)
                }
                Text(take.prompt.trimmed.nilIfEmpty ?? "No saved direction")
                    .font(CanonType.interface(9))
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
            }
            Spacer()
            if let onRepair,
               (!take.errorMessage.isEmpty && (take.segmentClip != nil || !take.providerOutputPath.isEmpty))
                || (!take.isReady && take.hasLocalRecoveryReceipt) {
                Button("REPAIR · $0") { onRepair(take.takeId) }
                    .buttonStyle(PlateButtonStyle()).disabled(isRendering)
            }
            if take.isReady {
                Button(previewed ? "PREVIEWING" : "PREVIEW") {
                    isPlaying = false
                    timestampSeconds = 0
                    previewTakeId = take.takeId
                }
                .buttonStyle(PlateButtonStyle())
                if !selected {
                    Button("USE") {
                        pendingImpact = branchImpact(take.takeId)
                    }
                    .buttonStyle(PlateButtonStyle())
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(previewed ? 0.58 : 0.28), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(previewed ? CanonColor.brass.opacity(0.7) : CanonColor.hairlinePaper, lineWidth: 1)
        )
    }

    private var impactTitle: String {
        guard let impact = pendingImpact else { return "Use this take?" }
        switch impact.resolution {
        case .selectCurrent:
            return "Use this take in the current Shot?"
        case .rechain(let ids):
            return "This changes \(ids.count) downstream continuation\(ids.count == 1 ? "" : "s")"
        }
    }

    private var impactMessage: String {
        guard let impact = pendingImpact else { return "" }
        switch impact.resolution {
        case .selectCurrent:
            return "Use this take in the current Shot. Play and export will follow the selected clips; no render version or provider request is created."
        case .rechain(let ids):
            return "Keeping later clips preserves them but marks their anchors stale. Rechain generates \(ids.count) new linked take\(ids.count == 1 ? "" : "s") in order; completed links remain resumable if a later one fails."
        }
    }
}
