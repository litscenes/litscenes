import SwiftUI

// The media viewer's generation surfaces: Restyle (image → restyled image),
// Start Video (image → motion clip), and the Video Studio's whole-asset
// Restyle (video → media-home Look). Small popovers over the engine's viewer
// ops — each states its refusal reason in place instead of hiding disabled.

/// Model + duration + optional motion prompt: image-to-video with no shot and
/// no scene. The clip lands as a top-level Footage tray asset.
struct MediaStartVideoPopover: View {
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    var onSubmitted: () -> Void

    @State private var model: ShotRenderModel = .wan27
    @State private var durationSeconds = ShotRenderModel.wan27.defaultDuration
    @State private var motionPrompt = ""
    @State private var generateAudio = true
    @State private var submissionError = ""

    private var recipe: ShotRenderStack {
        ShotRenderStack.recipe(
            model: model,
            durationSeconds: durationSeconds,
            generateAudio: generateAudio
        )
    }

    private var estimateLabel: String {
        if let usd = ShotRenderCostEstimate.segmentUSD(stack: recipe, pricing: library.falPricing) {
            return String(format: "EST. $%.2f", usd)
        }
        return "provider-priced"
    }

    private var submitBlockReason: String? {
        library.mediaMotionStartBlockReason(mediaId: item.mediaId, model: model)
            ?? submissionError.trimmed.nilIfEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("START VIDEO")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                Text(estimateLabel)
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(mediaMotionSelectableModels()) { candidate in
                        mediaGenerationChip(
                            label: candidate.label,
                            isSelected: model == candidate
                        ) {
                            model = candidate
                            durationSeconds = candidate.supportedDurations.contains(durationSeconds)
                                ? durationSeconds
                                : candidate.defaultDuration
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Picker("Length", selection: $durationSeconds) {
                    ForEach(model.supportedDurations, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                if model.supportsGeneratedAudio {
                    Toggle("Generate audio", isOn: $generateAudio)
                        .toggleStyle(.checkbox)
                        .font(CanonType.interface(11))
                }
                Spacer(minLength: 0)
            }
            TextField(mediaMotionDefaultPrompt(), text: $motionPrompt)
                .textFieldStyle(.roundedBorder)
                .font(CanonType.interface(12))
                .help("Optional — how the scene should move. Empty uses the default gentle-motion direction")
            HStack(spacing: 10) {
                Button {
                    let accepted = library.startMediaMotionRender(
                        mediaId: item.mediaId,
                        model: model,
                        durationSeconds: durationSeconds,
                        motionPrompt: motionPrompt,
                        generateAudio: generateAudio
                    )
                    if accepted {
                        submissionError = ""
                        onSubmitted()
                    } else {
                        submissionError = library.aestheticStatus.trimmed.nilIfEmpty
                            ?? "Could not start this video"
                    }
                } label: {
                    Label("Start Video", systemImage: "video.badge.plus")
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(submitBlockReason != nil)
                Spacer(minLength: 0)
            }
            if let reason = submitBlockReason {
                Text(reason)
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.rust)
            }
            Text("Renders from this image via FAL · lands top-level in Footage · logged to the spend ledger")
                .font(CanonType.interface(10))
                .foregroundStyle(CanonColor.muted)
        }
        .padding(14)
        .frame(width: 380)
        .onChange(of: model) { _, _ in submissionError = "" }
        .onChange(of: durationSeconds) { _, _ in submissionError = "" }
        .onChange(of: generateAudio) { _, _ in submissionError = "" }
    }
}

/// The Video Studio's whole-asset Restyle: the Clip Look composer's essentials
/// over the ENTIRE video, landing tray-only under the source. Style browsing
/// happens in a Studio-level sheet (the proven popover→sheet→reopen flow), so
/// the picker state is hoisted to the caller.
struct MediaLookComposerPopover: View {
    @AppStorage(ShotLookProvider.preferenceKey, store: LitScenesPreferences.store)
    private var providerRaw = ShotLookProvider.fal.rawValue
    @ObservedObject var library: LibraryEngine
    let item: MediaItemRecord
    @Binding var prompt: String
    @Binding var enhancePrompt: Bool
    @Binding var styleSelection: ShotLookStyleSelection?
    var onBrowseStyles: () -> Void
    var onSubmit: (ShotLookProvider) -> Void

    private var provider: ShotLookProvider { ShotLookProvider.resolved(providerRaw) }
    private var providerBinding: Binding<ShotLookProvider> {
        Binding(get: { provider }, set: { providerRaw = $0.rawValue })
    }
    private var durationSeconds: Double { max(item.durationSeconds ?? 0, 0) }
    private var composedPrompt: String {
        shotLookComposedPrompt(styleSummary: styleSelection?.summary ?? "", userText: prompt)
    }
    private var estimateLabel: String {
        provider == .fal
            ? String(format: "EST. $%.2f", durationSeconds * 0.01)
            : String(format: "EST. %.1f CREDITS", durationSeconds)
    }
    private var hasCredential: Bool {
        library.videoProviderCredentialStatuses
            .first(where: { $0.provider == provider.credentialProvider })?
            .isConfigured == true
    }
    private var submitBlockReason: String? {
        if library.isGenerationPaused { return "Generation is paused — resume to continue" }
        if library.clipLookLaneIsFull {
            return "\(library.clipLookLaneCap) Clip Looks are already running — wait for one to finish"
        }
        if !hasCredential {
            return "Add a \(provider == .fal ? "FAL" : "Decart") API key in App Settings"
        }
        if durationSeconds <= 0 || durationSeconds > 600.001 {
            return "Restyle sources run up to 10 minutes"
        }
        switch provider {
        case .fal:
            if composedPrompt.isEmpty { return nil }
        case .decart:
            if styleSelection?.hasUsableImageReference != true {
                return "Choose a verified catalog style for Decart image input"
            }
        }
        return nil
    }
    private var canSubmit: Bool {
        guard submitBlockReason == nil else { return false }
        switch provider {
        case .fal: return !composedPrompt.isEmpty && composedPrompt.count <= 1_500
        case .decart: return styleSelection?.hasUsableImageReference == true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("RESTYLE VIDEO")
                    .font(CanonType.archive(9, weight: .semibold))
                    .kerning(1.4)
                    .foregroundStyle(CanonColor.muted)
                Spacer(minLength: 0)
                Text("\(estimateLabel) · whole asset, audio kept")
                    .font(CanonType.interface(10))
                    .foregroundStyle(CanonColor.muted)
            }
            Picker("", selection: providerBinding) {
                Text("Lucy · FAL").tag(ShotLookProvider.fal)
                Text("Lucy · Decart").tag(ShotLookProvider.decart)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ShotLookStyleChipRow(
                styleSelection: $styleSelection,
                provider: provider,
                onBrowseStyles: onBrowseStyles
            )
            if provider == .fal {
                TextField("Describe the look — the style line leads, your notes follow", text: $prompt)
                    .textFieldStyle(.roundedBorder)
                    .font(CanonType.interface(12))
                Toggle("Enhance prompt", isOn: $enhancePrompt)
                    .toggleStyle(.checkbox)
                    .font(CanonType.interface(11))
            }
            HStack(spacing: 10) {
                Button {
                    onSubmit(provider)
                } label: {
                    Label("Restyle", systemImage: "paintpalette")
                }
                .buttonStyle(CanonPrimaryButtonStyle())
                .disabled(!canSubmit)
                Spacer(minLength: 0)
            }
            if let reason = submitBlockReason {
                Text(reason)
                    .font(CanonType.interface(10.5))
                    .foregroundStyle(CanonColor.rust)
            }
            Text("Nests under this video in the tray · original audio muxed back · cancel from the activity chip")
                .font(CanonType.interface(10))
                .foregroundStyle(CanonColor.muted)
        }
        .padding(14)
        .frame(width: 400)
    }
}

/// Small selectable chip shared by the viewer popovers.
@MainActor
@ViewBuilder
func mediaGenerationChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(CanonType.interface(10.5, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? CanonColor.paper : CanonColor.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? CanonColor.ink.opacity(0.85) : Color.white.opacity(0.45))
            )
            .overlay(Capsule().stroke(CanonColor.hairlinePaper))
            .contentShape(Capsule())
    }
    .buttonStyle(.plain)
}
