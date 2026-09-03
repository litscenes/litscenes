import SwiftUI

/// Seed slot for the per-take style picker: the take's assigned style authority when
/// resolvable, else the lens treatment's primary. Shared by every host of
/// LensTakeStylePickerModal (theater, scene-first Characters panel).
func lensTakeStyleSlot(for image: ProjectLensHeroImage, treatment: LensStyleTreatment?) -> LensStyleTreatmentSlot? {
    let preferredId = image.sourceAestheticIds.first ?? ""
    let authority = image.styleAuthorities
        .map { $0.normalized() }
        .first { !$0.referenceId.isEmpty && $0.referenceId == preferredId }
        ?? image.styleAuthorities.first?.normalized()
    if let authority, !authority.referenceId.isEmpty {
        return LensStyleTreatmentSlot(
            styleId: authority.referenceId,
            label: authority.title,
            collection: "",
            hueHex: "",
            url: authority.imageUrl.isEmpty ? authority.imagePath : authority.imageUrl,
            weight: authority.weight ?? 100
        )
    }
    return treatment?.primary
}

/// The per-take render-setup popover: stack chooser (render_stacks.yaml), style-mode
/// control, FAL parameter editor, style summary + Edit Style hand-off, and — for ready
/// takes — the WAN motion-artifact panel. Extracted from LensGenerationTheaterView so
/// the scene-first Characters sidebar can offer the identical flow; both hosts present
/// it from their own `.popover(item:)`. Stack/style-mode/parameter drafts are local
/// state and reset per opening.
struct LensTakeRenderSetupPopover: View {
    let image: ProjectLensHeroImage
    /// FAL debug-parameter templates derive from the lens's media plan.
    let mediaPlan: LensMediaPlan
    var hasOpenAICredential: Bool = true
    var hasCivitaiCredential: Bool = false
    var hasFALCredential: Bool = false
    var hasStabilityCredential: Bool = false
    /// True while another render runs or generation is paused; rows stay browsable
    /// but submission is blocked with the notice below.
    var isRenderBlocked: Bool = false
    var renderBlockerHelp: String? = nil
    /// Distinguishes the paused notice from the busy notice.
    var isPaused: Bool = false
    var isAnimatingLensArtifact: Bool = false
    var onSubmit: (LensTakeRenderRequest) -> Void
    /// Ready takes only: regenerate/animate the WAN motion artifact. Nil disables.
    var onAnimate: (() -> Void)? = nil
    /// Opens the host's per-take style picker. Nil hides the Edit Style button.
    var onEditStyle: (() -> Void)? = nil
    var onOpenAppSettings: (() -> Void)? = nil
    var onDismiss: () -> Void

    @State private var activeStillStack: RenderStack?
    @State private var styleModeByStack: [String: LensRenderStyleMode] = [:]
    @State private var debugParametersByStack: [String: String] = [:]

    var body: some View {
        let isReady = image.status == "ready"
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isReady ? "Motion Artifact" : "Render Take")
                        .font(CanonType.interface(14, weight: .semibold))
                        .foregroundStyle(CanonColor.ink)
                    Text(image.label.trimmed.isEmpty ? "Planned take" : image.label)
                        .font(CanonType.archive(9, weight: .semibold))
                        .kerning(0.6)
                        .foregroundStyle(CanonColor.muted)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CanonColor.ink.opacity(0.55))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            if isReady {
                VStack(alignment: .leading, spacing: 7) {
                    Text("LENS MOTION")
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(CanonColor.muted)
                    renderStatusStackOption(
                        title: "WAN 2.5 Image-to-Video",
                        detail: "Civitai · 5 seconds · generated from this frame",
                        status: motionStatusLabel(image),
                        icon: "film.fill",
                        isSelected: true,
                        isLocked: false
                    )
                    motionArtifactSummary(image)
                }

                Button {
                    onDismiss()
                    onAnimate?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(motionButtonTitle(image))
                            .font(CanonType.interface(11.5, weight: .semibold))
                    }
                    .foregroundStyle(CanonColor.paper)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.brass))
                }
                .buttonStyle(.plain)
                .disabled(onAnimate == nil || isAnimatingLensArtifact || image.motionArtifact?.normalized().status == "generating")
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    Text("LENS STACK")
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(CanonColor.muted)
                    // Stacks come from render_stacks.yaml (defaults + user
                    // overlay) — same list as the Frame Creator.
                    ForEach(RenderStackRegistry.shared.stacks()) { stack in
                        renderStackOption(
                            title: stack.label,
                            detail: stack.detail,
                            icon: renderStackIcon(for: stack),
                            stack: stack
                        )
                    }
                }

                Divider().background(CanonColor.hairlinePaper.opacity(0.7))

                VStack(alignment: .leading, spacing: 7) {
                    Text("STYLE")
                        .font(CanonType.archive(8, weight: .semibold))
                        .kerning(1.1)
                        .foregroundStyle(CanonColor.muted)
                    styleSetupSummary(image)
                    if onEditStyle != nil {
                        Button {
                            onDismiss()
                            onEditStyle?()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Edit Style")
                                    .font(CanonType.interface(11, weight: .semibold))
                            }
                            .foregroundStyle(CanonColor.brass)
                            .frame(height: 26)
                        }
                        .buttonStyle(.plain)
                        .help("Choose the catalog style for this take only")
                    }
                }

                if isRenderBlocked {
                    renderBlockerNotice
                }
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(CanonColor.paper)
    }

    // MARK: - Stacks

    private var canUseFAL: Bool {
        hasFALCredential && hasOpenAICredential
    }

    private var falStackIcon: String {
        canUseFAL ? "bolt.fill" : "lock.fill"
    }

    private func renderStackIcon(for stack: RenderStack) -> String {
        switch stack.credentialProvider {
        case .openAI:
            return hasOpenAICredential ? "sparkles" : "lock.fill"
        case .civitai:
            return hasCivitaiCredential ? "square.stack.3d.up.fill" : "lock.fill"
        case .fal:
            return falStackIcon
        case .stability:
            return hasStabilityCredential && hasOpenAICredential ? "photo.on.rectangle.angled" : "lock.fill"
        default:
            return "lock.fill"
        }
    }

    private func renderStackOption(
        title: String,
        detail: String,
        icon: String,
        stack: RenderStack
    ) -> some View {
        let isActive = activeStillStack == stack
        let credentialBlocker = renderCredentialBlocker(for: stack)
        let startBlocker = renderStartBlocker(stack: stack)
        let isLocked = credentialBlocker != nil
        let rowDisabled = !isLocked && isActive && startBlocker != nil
        return VStack(alignment: .leading, spacing: 6) {
            if isLocked {
                renderLockedStackRow(
                    title: title,
                    detail: detail,
                    icon: icon,
                    credentialBlocker: credentialBlocker ?? ""
                )
            } else {
                Button {
                    if isActive {
                        guard startBlocker == nil else { return }
                        submitStillRender(stack: stack)
                    } else {
                        withAnimation(.easeOut(duration: 0.16)) {
                            activeStillStack = stack
                            seedDebugParametersIfNeeded(stack: stack)
                        }
                    }
                } label: {
                    renderStackRowChrome(
                        title: title,
                        detail: detail,
                        icon: icon,
                        isSelected: isActive,
                        isLocked: false
                    ) {
                        LitIconView(icon: .keyReturn, size: 16)
                            .foregroundStyle(isActive ? CanonColor.brass : CanonColor.muted)
                    }
                }
                .buttonStyle(.plain)
                .disabled(rowDisabled)
                .opacity(isRenderBlocked && !isActive ? 0.72 : 1)
                .help(startBlocker ?? (isActive ? "Click again to start this render" : "Open \(stack.label) render controls"))
            }

            if isActive {
                renderStackControls(stack: stack)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private func renderLockedStackRow(
        title: String,
        detail: String,
        icon: String,
        credentialBlocker: String
    ) -> some View {
        renderStackRowChrome(
            title: title,
            detail: detail,
            icon: icon,
            isSelected: false,
            isLocked: true
        ) {
            HStack(spacing: 2) {
                Text("Needs API key -")
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(0.45)
                    .foregroundStyle(CanonColor.muted)
                Button {
                    onDismiss()
                    onOpenAppSettings?()
                } label: {
                    Text("add now")
                        .font(CanonType.archive(7.5, weight: .bold))
                        .kerning(0.45)
                        .foregroundStyle(CanonColor.brass)
                        .underline()
                }
                .buttonStyle(.plain)
                .help(credentialBlocker)
            }
        }
    }

    private func renderStackRowChrome<Trailing: View>(
        title: String,
        detail: String,
        icon: String,
        isSelected: Bool,
        isLocked: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isLocked ? CanonColor.ink.opacity(0.32) : CanonColor.brass)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(isLocked ? CanonColor.ink.opacity(0.42) : CanonColor.ink.opacity(0.82))
                Text(detail)
                    .font(CanonType.archive(8, weight: .medium))
                    .kerning(0.25)
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? CanonColor.softGold.opacity(0.18) : CanonColor.paperInset.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? CanonColor.brass.opacity(0.45) : CanonColor.hairlinePaper.opacity(0.7), lineWidth: 1)
        )
    }

    private func renderStatusStackOption(
        title: String,
        detail: String,
        status: String,
        icon: String,
        isSelected: Bool,
        isLocked: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isLocked ? CanonColor.ink.opacity(0.32) : CanonColor.brass)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CanonType.interface(11, weight: .semibold))
                    .foregroundStyle(isLocked ? CanonColor.ink.opacity(0.42) : CanonColor.ink.opacity(0.82))
                Text(detail)
                    .font(CanonType.archive(8, weight: .medium))
                    .kerning(0.25)
                    .foregroundStyle(CanonColor.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(status)
                .font(CanonType.archive(7.5, weight: .bold))
                .kerning(0.8)
                .foregroundStyle(isSelected ? CanonColor.olive : CanonColor.muted)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? CanonColor.softGold.opacity(0.18) : CanonColor.paperInset.opacity(0.52))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? CanonColor.brass.opacity(0.45) : CanonColor.hairlinePaper.opacity(0.7), lineWidth: 1)
        )
    }

    // MARK: - Style mode + FAL parameters

    private func renderStackControls(stack: RenderStack) -> some View {
        let styleMode = effectiveStyleMode(for: stack)
        let debugError = stack.isFAL
            ? FALImageClient.validateDebugParameters(debugParameters(for: stack), stack: stack, styleMode: styleMode)
            : ""
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Text("STYLE MODE")
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.muted)
                Spacer()
                if stack.isFAL {
                    Text(stack.falModelId(styleMode: styleMode))
                        .font(CanonType.archive(7.2, weight: .medium))
                        .kerning(0.2)
                        .foregroundStyle(CanonColor.ink.opacity(0.42))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            styleModeControl(stack: stack)

            if stack.isFAL {
                Text("PARAMETERS")
                    .font(CanonType.archive(7.5, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(CanonColor.muted)
                    .padding(.top, 2)
                TextEditor(text: debugParametersBinding(for: stack))
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(CanonColor.ink)
                    .scrollContentBackground(.hidden)
                    .frame(height: 112)
                    .padding(5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(CanonColor.paperInset.opacity(0.65)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(debugError.isEmpty ? CanonColor.hairlinePaper.opacity(0.7) : CanonColor.rust.opacity(0.7), lineWidth: 1))
                if !debugError.isEmpty {
                    Text(debugError)
                        .font(CanonType.interface(9.5, weight: .medium))
                        .foregroundStyle(CanonColor.rust)
                        .lineLimit(3)
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.paperInset.opacity(0.52)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.72), lineWidth: 1))
    }

    private func styleModeControl(stack: RenderStack) -> some View {
        let selected = effectiveStyleMode(for: stack)
        return HStack(spacing: 4) {
            ForEach(styleModeOptions(for: stack), id: \.self) { mode in
                Button {
                    styleModeByStack[stack.id] = mode
                    if stack.isFAL {
                        debugParametersByStack[stack.id] = stack.falDebugParameterTemplate(
                            mediaPlan: mediaPlan,
                            styleMode: mode
                        )
                    }
                } label: {
                    Text(mode.shortLabel)
                        .font(CanonType.interface(9.8, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(selected == mode ? CanonColor.paper : CanonColor.ink.opacity(0.68))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selected == mode ? CanonColor.brass : CanonColor.paper.opacity(0.55))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func styleModeOptions(for stack: RenderStack) -> [LensRenderStyleMode] {
        guard !image.styleAuthorities.isEmpty else { return [.none] }
        var modes: [LensRenderStyleMode] = [.none, .describeStyleInPrompt]
        if stack.styleImageAttachSupported {
            modes.append(.attachStyleImage)
        }
        return modes
    }

    private func effectiveStyleMode(for stack: RenderStack) -> LensRenderStyleMode {
        let fallback: LensRenderStyleMode = image.styleAuthorities.isEmpty ? .none : .describeStyleInPrompt
        let selected = styleModeByStack[stack.id] ?? fallback
        return styleModeOptions(for: stack).contains(selected) ? selected : fallback
    }

    private func debugParameters(for stack: RenderStack) -> String {
        debugParametersByStack[stack.id] ?? stack.falDebugParameterTemplate(
            mediaPlan: mediaPlan,
            styleMode: effectiveStyleMode(for: stack)
        )
    }

    private func debugParametersBinding(for stack: RenderStack) -> Binding<String> {
        Binding(
            get: { debugParameters(for: stack) },
            set: { debugParametersByStack[stack.id] = $0 }
        )
    }

    private func seedDebugParametersIfNeeded(stack: RenderStack) {
        guard stack.isFAL, debugParametersByStack[stack.id] == nil else { return }
        debugParametersByStack[stack.id] = stack.falDebugParameterTemplate(
            mediaPlan: mediaPlan,
            styleMode: effectiveStyleMode(for: stack)
        )
    }

    // MARK: - Blockers + submit

    private func renderCredentialBlocker(for stack: RenderStack) -> String? {
        switch stack.credentialProvider {
        case .openAI:
            return hasOpenAICredential ? nil : "Add an OpenAI API key in App Settings."
        case .civitai:
            return hasCivitaiCredential ? nil : "Add a CivitAI API key in App Settings."
        case .fal:
            if !hasFALCredential { return "Add a FAL API key in App Settings." }
            if !hasOpenAICredential { return "Add an OpenAI API key for prompt writing." }
            return nil
        case .stability:
            if !hasStabilityCredential { return "Add a Stability AI API key in App Settings." }
            if !hasOpenAICredential { return "Add an OpenAI API key for prompt writing." }
            return nil
        default:
            return "\(stack.credentialProvider.label) key gating is not supported for render stacks."
        }
    }

    private func renderStartBlocker(stack: RenderStack) -> String? {
        if let renderBlockerHelp { return renderBlockerHelp }
        let styleMode = effectiveStyleMode(for: stack)
        if styleMode == .attachStyleImage, image.styleAuthorities.isEmpty {
            return "Choose a style before attaching a style image."
        }
        if stack.isFAL {
            let debugError = FALImageClient.validateDebugParameters(
                debugParameters(for: stack),
                stack: stack,
                styleMode: styleMode
            )
            if !debugError.isEmpty { return debugError }
        }
        return nil
    }

    private func submitStillRender(stack: RenderStack) {
        let styleMode = effectiveStyleMode(for: stack)
        let debugJSON = stack.isFAL ? debugParameters(for: stack) : ""
        onDismiss()
        onSubmit(
            LensTakeRenderRequest(
                stack: stack,
                styleMode: styleMode,
                debugParametersJSON: debugJSON
            )
        )
    }

    private var renderBlockerNotice: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: isPaused ? "pause.circle.fill" : "clock.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CanonColor.brass)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(isPaused ? "Rendering is paused" : "A Scene Plan render is already running")
                    .font(CanonType.interface(10.5, weight: .semibold))
                    .foregroundStyle(CanonColor.ink.opacity(0.78))
                Text(isPaused
                    ? "Resume before starting a new still render. This style change is saved; no render has started."
                    : "Wait for the active render to finish before starting another still. This style change is saved.")
                    .font(CanonType.interface(9.5))
                    .foregroundStyle(CanonColor.ink.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.brass.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.brass.opacity(0.34), lineWidth: 1))
    }

    // MARK: - Motion

    private func motionStatusLabel(_ image: ProjectLensHeroImage) -> String {
        switch image.motionArtifact?.normalized().status {
        case "ready": return "READY"
        case "generating": return "GENERATING"
        case "failed": return "FAILED"
        default: return "AVAILABLE"
        }
    }

    private func motionButtonTitle(_ image: ProjectLensHeroImage) -> String {
        image.motionArtifact?.normalized().status == "ready"
            ? "Regenerate WAN 2.5 Motion"
            : "Animate with WAN 2.5"
    }

    private func motionArtifactSummary(_ image: ProjectLensHeroImage) -> some View {
        let artifact = image.motionArtifact?.normalized()
        let status = artifact?.status ?? ""
        let error = artifact?.errorMessage ?? ""
        let path = artifact?.videoPath ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            if status == "ready", !path.isEmpty {
                Text("Motion ready · \(URL(fileURLWithPath: path).lastPathComponent)")
            } else if status == "generating" {
                Text("WAN 2.5 motion is rendering for this artifact.")
            } else if status == "failed", !error.isEmpty {
                Text(error)
            } else {
                Text("Uses the rendered frame as the first frame. Still-image style stays on the source artifact.")
            }
        }
        .font(CanonType.interface(10))
        .foregroundStyle(status == "failed" ? CanonColor.rust : CanonColor.ink.opacity(0.58))
        .lineLimit(3)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.paperInset.opacity(0.52)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.7), lineWidth: 1))
    }

    // MARK: - Style summary

    private func styleSetupSummary(_ image: ProjectLensHeroImage) -> some View {
        let style = image.styleAuthorities.first?.normalized()
        let title = style?.title.trimmed ?? ""
        let summary = style?.oneLineStyleSummary.trimmed ?? ""
        return VStack(alignment: .leading, spacing: 4) {
            Text(title.isEmpty ? "Goal-derived Scene Plan style" : title)
                .font(CanonType.interface(11, weight: .semibold))
                .foregroundStyle(CanonColor.ink.opacity(0.82))
                .lineLimit(1)
            Text(summary.isEmpty ? "This take uses the current Scene Plan style. Choose Edit Style to change only this planned take." : summary)
                .font(CanonType.interface(10))
                .foregroundStyle(CanonColor.ink.opacity(0.58))
                .lineLimit(3)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(CanonColor.paperInset.opacity(0.52)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CanonColor.hairlinePaper.opacity(0.7), lineWidth: 1))
    }
}
