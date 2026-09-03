import SwiftUI

/// The one style-selection surface shared by the Shot Look composer and the
/// Clip Look section: chip (thumb, hue dot, label, CHANGE, ×) when chosen,
/// BROWSE STYLES… when empty, plus provider-accurate input provenance.
struct ShotLookStyleChipRow: View {
    @Binding var styleSelection: ShotLookStyleSelection?
    var provider: ShotLookProvider = .fal
    var onBrowseStyles: () -> Void

    var body: some View {
        if let selection = styleSelection {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 9) {
                    AsyncImage(url: URL(string: selection.url)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(PlateColor.creamDeep)
                    }
                    .frame(width: 34, height: 34)
                    .clipped()
                    .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(canonColor(fromHex: selection.hueHex))
                                .frame(width: 6, height: 6)
                            PlateLabel(text: selection.label, size: 8.5, weight: .semibold)
                                .lineLimit(1)
                        }
                        if !selection.collection.trimmed.isEmpty {
                            PlateLabel(text: selection.collection, size: 7.5, color: PlateColor.inkFaint)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 6)
                    Button("CHANGE", action: onBrowseStyles)
                        .buttonStyle(PlateButtonStyle())
                    Button {
                        styleSelection = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PlateColor.inkFaint)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the style — your notes stay")
                }
                .padding(6)
                .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
                Text(provider == .decart
                    ? (selection.hasUsableImageReference
                        ? "Verified catalog image attached · SHA-256 \(selection.imageReference?.sha256.prefix(12) ?? "")…"
                        : "Reselect this style to attach its verified catalog image.")
                    : "Style direction: \(selection.summary.trimmed)")
                    .font(.system(size: 9.5, design: .serif))
                    .foregroundStyle(PlateColor.inkFaint)
                    .lineLimit(2)
                    .help(provider == .decart
                        ? "Decart receives this catalog image directly; no text prompt is sent."
                        : "This line leads the prompt sent to Lucy; your notes follow it.")
            }
        } else {
            HStack(spacing: 10) {
                PlateLabel(text: "STYLE", size: 8, color: PlateColor.inkFaint)
                Button("BROWSE STYLES…", action: onBrowseStyles)
                    .buttonStyle(PlateButtonStyle())
                Text(provider == .decart ? "required · image input" : "optional · leads the prompt")
                    .font(.system(size: 9.5, design: .serif))
                    .foregroundStyle(PlateColor.inkFaint)
                Spacer()
            }
        }
    }
}

struct ShotRestyleComposer: View {
    @AppStorage(ShotLookProvider.preferenceKey, store: LitScenesPreferences.store)
    private var providerRaw = ShotLookProvider.fal.rawValue
    @Binding var prompt: String
    @Binding var enhancePrompt: Bool
    @Binding var seed: Int
    @Binding var styleSelection: ShotLookStyleSelection?
    let sourceDurationSeconds: Double
    let hasFALCredential: Bool
    let hasDecartCredential: Bool
    let isVideoOperationBlocked: Bool
    let activeLook: ShotRestyleArtifact?
    let recoverableLook: ShotRestyleArtifact?
    var onSubmit: (ShotLookProvider) -> Void
    var onCancel: () -> Void
    var onRetry: (String) -> Void
    var onBrowseStyles: () -> Void

    private var cleanPrompt: String { String(prompt.trimmed.prefix(1_500)) }
    private var provider: ShotLookProvider { ShotLookProvider.resolved(providerRaw) }
    private var providerBinding: Binding<ShotLookProvider> {
        Binding(
            get: { provider },
            set: { providerRaw = $0.rawValue }
        )
    }
    /// The exact text the engine will submit: the chosen style's
    /// "Style direction" line first, then the operator's notes.
    private var composedPrompt: String {
        shotLookComposedPrompt(styleSummary: styleSelection?.summary ?? "", userText: prompt)
    }
    private var estimatedCost: Double { max(sourceDurationSeconds, 0) * 0.01 }
    private var estimatedCredits: Double { max(sourceDurationSeconds, 0) }
    private var estimatedCostLabel: String {
        provider == .fal
            ? String(format: "EST. $%.2f", estimatedCost)
            : String(format: "EST. %.1f CREDITS", estimatedCredits)
    }
    private var hasSelectedCredential: Bool {
        provider == .fal ? hasFALCredential : hasDecartCredential
    }
    private var hasExecutableInput: Bool {
        switch provider {
        case .fal: !composedPrompt.isEmpty && composedPrompt.count <= 1_500
        case .decart: styleSelection?.hasUsableImageReference == true
        }
    }
    private var durationIsSupported: Bool { sourceDurationSeconds > 0 && sourceDurationSeconds <= 600.001 }
    private var canSubmit: Bool {
        hasSelectedCredential
            && !isVideoOperationBlocked
            && activeLook == nil
            && durationIsSupported
            && hasExecutableInput
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PlateLabel(text: "SHOT LOOK", size: 11, weight: .bold)
                Rectangle().fill(PlateColor.hairline).frame(height: 1)
                PlateLabel(text: "LUCY", size: 8.5, color: PlateColor.inkFaint)
            }

            HStack(spacing: 8) {
                fact("MODEL", "LUCY RESTYLE")
                fact("OUTPUT", "720P")
                fact("SOURCE", durationText(sourceDurationSeconds))
                Spacer(minLength: 4)
                PlateLabel(
                    text: estimatedCostLabel,
                    size: 9,
                    weight: .bold,
                    color: CanonColor.brass
                )
            }

            styleRow

            if provider == .fal {
                promptEditor
            } else {
                referenceImageInput
            }

            HStack(spacing: 12) {
                if provider == .fal {
                    Toggle("Enhance prompt", isOn: $enhancePrompt)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10, weight: .medium, design: .serif))
                } else {
                    PlateLabel(text: "NO TEXT PROMPT · ENHANCE OFF", size: 8, color: PlateColor.inkFaint)
                }
                Spacer()
                PlateLabel(text: "SEED", size: 8, color: PlateColor.inkFaint)
                TextField("Seed", value: $seed, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .frame(width: 92)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
                if provider == .fal {
                    PlateLabel(
                        text: "\(composedPrompt.count)/1500",
                        size: 8,
                        color: composedPrompt.count > 1_500 ? CanonColor.rust : PlateColor.inkFaint
                    )
                }
            }

            if let activeLook {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        PlateLabel(
                            text: activeLook.status.uppercased(),
                            size: 8.5,
                            weight: .bold,
                            color: CanonColor.brass
                        )
                        Spacer()
                        Button(activeLook.restyleProvider == .decart && !activeLook.requestId.isEmpty
                            ? "STOP WAITING"
                            : "CANCEL", action: onCancel)
                            .buttonStyle(PlateButtonStyle())
                    }
                    if activeLook.restyleProvider == .decart && !activeLook.requestId.isEmpty {
                        Text("Stops local monitoring only. Decart may keep processing or charging; Resume Look reuses this job.")
                            .font(.system(size: 9, design: .serif))
                            .foregroundStyle(CanonColor.rust)
                    }
                }
            } else {
                warning
                HStack {
                    if let recoverableLook,
                       !recoverableLook.requestId.isEmpty,
                       recoveryIsRetryable(recoverableLook) {
                        Button(recoverableLook.outputRemoteURL.isEmpty ? "RESUME LOOK" : "RETRY DOWNLOAD") {
                            onRetry(recoverableLook.versionId)
                        }
                        .buttonStyle(PlateButtonStyle())
                        .disabled(!credentialAvailable(for: recoverableLook) || isVideoOperationBlocked)
                        .help(recoverableLook.errorMessage)
                    }
                    Spacer()
                    Button("CREATE LOOK · \(estimatedCostLabel)") {
                        onSubmit(provider)
                    }
                        .buttonStyle(PlateButtonStyle(isProminent: true))
                        .disabled(!canSubmit)
                }
            }

            Text("Picture only · Original preserved · Source, Narration, and Mic remain editable")
                .font(.system(size: 9, design: .serif))
                .foregroundStyle(PlateColor.inkFaint)
        }
        .padding(16)
        .frame(width: 438)
        .background(PlateColor.cream)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder
    private var warning: some View {
        if !hasSelectedCredential {
            warningLine("Add a \(provider == .fal ? "FAL" : "Decart") API key in App Settings before creating a Look.")
        } else if !durationIsSupported {
            warningLine(sourceDurationSeconds <= 0
                ? "The Original needs playable picture before it can be restyled."
                : "Lucy Look sources are currently limited to 10 minutes.")
        } else if isVideoOperationBlocked {
            warningLine("Wait for the current video operation to finish.")
        } else if provider == .fal && composedPrompt.count > 1_500 {
            warningLine("Style direction plus notes exceed 1500 characters — trim the notes.")
        } else if provider == .decart && styleSelection == nil {
            warningLine("Choose a catalog style to attach as Decart's image input.")
        } else if provider == .decart && styleSelection?.hasUsableImageReference != true {
            warningLine("Reselect this style so its verified catalog image can be attached.")
        } else if let recoverableLook, !recoverableLook.errorMessage.trimmed.isEmpty {
            warningLine(String(recoverableLook.errorMessage.trimmed.prefix(260)))
        }
    }

    private var styleRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                PlateLabel(text: "PROVIDER", size: 7.5, color: PlateColor.inkFaint)
                Picker("Provider", selection: providerBinding) {
                    ForEach(ShotLookProvider.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            ShotLookStyleChipRow(
                styleSelection: $styleSelection,
                provider: provider,
                onBrowseStyles: onBrowseStyles
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var promptEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $prompt)
                .font(.system(size: 12.5, design: .serif))
                .foregroundStyle(PlateColor.ink)
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(minHeight: 124, maxHeight: 168)
                .background(PlateColor.creamDeep.opacity(0.34))
                .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
                .onChange(of: prompt) { _, value in
                    if value.count > 1_500 { prompt = String(value.prefix(1_500)) }
                }
            if cleanPrompt.isEmpty {
                Text(styleSelection == nil
                    ? "Describe the visual treatment Lucy should apply to the whole edited Shot…"
                    : "Optional refinement notes — the chosen style leads this Look…")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(PlateColor.inkFaint)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var referenceImageInput: some View {
        HStack(alignment: .top, spacing: 12) {
            if let selection = styleSelection {
                AsyncImage(url: URL(string: selection.url)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(PlateColor.creamDeep)
                }
                .frame(width: 96, height: 96)
                .clipped()
                .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
            } else {
                Rectangle()
                    .fill(PlateColor.creamDeep.opacity(0.45))
                    .frame(width: 96, height: 96)
                    .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 7) {
                PlateLabel(text: "REFERENCE IMAGE INPUT", size: 8.5, weight: .bold)
                Text("Decart receives the selected catalog image directly. No text prompt or refinement notes are sent for Lucy Restyle 2 image mode.")
                    .font(.system(size: 10.5, design: .serif))
                    .foregroundStyle(PlateColor.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                if let reference = styleSelection?.imageReference?.normalized() {
                    PlateLabel(
                        text: "\(reference.catalogVersion) · SHA \(reference.sha256.prefix(12))…",
                        size: 7.5,
                        color: PlateColor.inkFaint
                    )
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(minHeight: 118)
        .background(PlateColor.creamDeep.opacity(0.24))
        .overlay(Rectangle().stroke(PlateColor.hairline, lineWidth: 1))
    }

    private func warningLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(CanonColor.rust)
            Text(text)
                .font(.system(size: 10, design: .serif))
                .foregroundStyle(CanonColor.rust)
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            PlateLabel(text: label, size: 7.5, color: PlateColor.inkFaint)
            PlateLabel(text: value, size: 8.5, weight: .semibold, color: PlateColor.ink)
        }
    }

    private func durationText(_ seconds: Double) -> String {
        let rounded = max(Int(seconds.rounded()), 0)
        return rounded >= 60 ? "\(rounded / 60)M \(rounded % 60)S" : "~\(rounded)S"
    }

    private func recoveryIsRetryable(_ look: ShotRestyleArtifact) -> Bool {
        look.restyleProvider == .decart
            || !look.errorMessage.localizedCaseInsensitiveContains("handoff is no longer accessible")
    }

    private func credentialAvailable(for look: ShotRestyleArtifact) -> Bool {
        look.restyleProvider == .fal ? hasFALCredential : hasDecartCredential
    }
}
