import Foundation

extension RenderStack {
    /// Capability of the executable image route, including native edit recipes.
    func styleAttachmentUnavailableReason(hasPromptImages: Bool) -> String? {
        if hasPromptImages, !supportsPromptImages {
            return "This model cannot receive the source frame. Style is available through Describe only."
        }
        if hasPromptImages, isStability || nativePromptImageLimit == 1 {
            return "This model accepts only one image, used by the source frame. Use Describe for style."
        }
        let supportsStyle: Bool
        switch kind {
        case .openai: supportsStyle = supportsPromptImages
        case .fal: supportsStyle = canAttachStyleImage && !styleModel.isEmpty
        case .stability: supportsStyle = styleImageAttachSupported
        case .civitai: supportsStyle = civitaiImageInputMode == .editImages && supportsPromptImages
        }
        guard supportsStyle, nativePromptImageLimit != 0 else {
            return "This model's image route cannot attach a style reference. Use Describe."
        }
        return nil
    }

    func frameStyleMode(hasStyle: Bool, isRestyle: Bool, preferred: LensRenderStyleMode?, hasPromptImages: Bool) -> LensRenderStyleMode {
        guard hasStyle else { return .none }
        let canAttach = styleAttachmentUnavailableReason(hasPromptImages: hasPromptImages) == nil
        let fallback: LensRenderStyleMode = isRestyle && canAttach ? .attachStyleImage : .describeStyleInPrompt
        guard let preferred else { return fallback }
        return preferred == .attachStyleImage && !canAttach ? .describeStyleInPrompt : preferred
    }

    /// Style occupies a native slot; the source remains first among content references.
    func framePromptReferenceCapacity(styleMode: LensRenderStyleMode) -> FrameReferenceCapacity {
        guard styleMode == .attachStyleImage, case .slots(let count) = frameReferenceCapacity else {
            return frameReferenceCapacity
        }
        return .slots(max(0, count - 1))
    }

    func frameStyleRequestError(styleMode: LensRenderStyleMode, promptImageCount: Int) -> String? {
        guard styleMode == .attachStyleImage else { return nil }
        if let reason = styleAttachmentUnavailableReason(hasPromptImages: promptImageCount > 0) { return reason }
        if let limit = nativePromptImageLimit, promptImageCount + 1 > limit {
            return "The style image and references exceed this model's \(limit)-image limit. Review the references before rendering."
        }
        return nil
    }
}

extension LensRenderRecipeSnapshot {
    /// Keep the creative choice separate from an adapter's edit-endpoint selector.
    func recordingStyleMode(_ mode: LensRenderStyleMode?) -> Self {
        guard let mode else { return self }
        var value = self
        value.parameters.removeAll { $0.key == "style_mode" }
        value.parameters.append(LensRenderRecipeParameter(key: "style_mode", value: mode.rawValue))
        return value
    }
}
