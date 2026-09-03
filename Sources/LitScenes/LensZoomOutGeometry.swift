import CoreGraphics
import Foundation

/// Pure geometry for the Zoom Out pipeline: planning the provider-native canvas
/// for mask-based outpainting and mapping the provider result into the final
/// frame so the wider view honors the operator's chosen source placement and
/// scale exactly.
enum LensZoomOutGeometry {

    /// A provider-native canvas plan for mask-based zoom-out (OpenAI).
    struct CanvasPlan: Equatable {
        var canvasWidth: Int
        var canvasHeight: Int
        /// Largest centered sub-rect of the canvas with the source aspect —
        /// the region that becomes the final frame after compositing.
        var finalFrame: CGRect
        /// Where the original source pixels are drawn, in CG (bottom-left
        /// origin) canvas coordinates.
        var sourceDrawRect: CGRect

        /// The explicit size parameter for the provider request. "auto" is
        /// never used: an unplanned output size cannot be aligned afterwards.
        var sizeString: String { "\(canvasWidth)x\(canvasHeight)" }
    }

    /// Where the original source content sits inside a provider result, in
    /// top-left-origin pixel coordinates of the canvas the request described.
    struct ProviderGeometry: Equatable {
        var canvasWidth: Int
        var canvasHeight: Int
        var sourceRegion: CGRect
    }

    /// The output sizes gpt-image models can return.
    static let providerCanvasSizes: [(width: Int, height: Int)] = [
        (1536, 1024), (1024, 1024), (1024, 1536)
    ]

    /// The smallest source scale a single outpaint pass may use. At 0.60 the
    /// worst one-sided expansion of a 1024px source is (0.4/0.6)·1024 ≈ 683px,
    /// inside FAL's 700px per-edge cap — so a pass never downscales its
    /// source — and per-pass invention stays bounded enough that providers
    /// continue structure instead of restating the composition.
    static let minimumPerPassSourceScale = 0.60
    static let maximumZoomOutPassCount = 4

    /// How many chained Zoom Out takes a total source scale requires.
    static func zoomOutPassCount(totalScale: Double) -> Int {
        guard totalScale > 0, totalScale < minimumPerPassSourceScale else { return 1 }
        let passes = Int((log(totalScale) / log(minimumPerPassSourceScale)).rounded(.up))
        return min(maximumZoomOutPassCount, max(1, passes))
    }

    /// Decomposes the spec's zoom-out into per-pass normalized source rects,
    /// one per chained take, each expressed in ITS pass's output frame. The
    /// margin fractions stay constant across passes, so composing the rects
    /// reproduces the total rect exactly (geometric series:
    /// total left margin = f_L·(1−Π sᵢ)).
    static func zoomOutPassRects(spec: LensReframeSpec) -> [CGRect] {
        let total = normalizedSourceRect(spec)
        let totalScale = Double(total.width)
        guard totalScale > 0, totalScale < 1 else { return [total] }
        let passes = zoomOutPassCount(totalScale: totalScale)
        guard passes > 1 else { return [total] }
        let horizontalMargin = Double(1 - total.width)
        let verticalMargin = Double(1 - total.height)
        let leftFraction = horizontalMargin > 0 ? Double(total.minX) / horizontalMargin : 0.5
        let topFraction = verticalMargin > 0 ? Double(total.minY) / verticalMargin : 0.5
        let passScale = pow(totalScale, 1.0 / Double(passes))
        let rect = CGRect(
            x: leftFraction * (1 - passScale),
            y: topFraction * (1 - passScale),
            width: passScale,
            height: passScale
        )
        return Array(repeating: rect, count: passes)
    }

    /// The zoom-out source rect with its origin clamped so the square always
    /// fits inside the unit frame. The UI clamps the center per the current
    /// scale, but enlarging the scale after an edge placement can push the raw
    /// rect out of bounds; every geometry consumer must share one answer.
    static func normalizedSourceRect(_ spec: LensReframeSpec) -> CGRect {
        let rect = spec.zoomOutSourceRect
        guard rect.width > 0, rect.height > 0 else { return rect }
        return CGRect(
            x: min(max(0, rect.minX), max(0, 1 - rect.width)),
            y: min(max(0, rect.minY), max(0, 1 - rect.height)),
            width: min(1, rect.width),
            height: min(1, rect.height)
        )
    }

    static func canvasPlan(
        sourceWidth: Int,
        sourceHeight: Int,
        spec: LensReframeSpec
    ) -> CanvasPlan? {
        canvasPlan(
            outputAspectWidth: sourceWidth,
            outputAspectHeight: sourceHeight,
            sourceRect: normalizedSourceRect(spec)
        )
    }

    /// Plans the provider canvas for an arbitrary normalized source placement
    /// inside an output frame of the given aspect. Zoom Out passes its square
    /// spec rect (source aspect == output aspect); terrain growth passes
    /// anisotropic edge rects into a grown-canvas aspect.
    static func canvasPlan(
        outputAspectWidth: Int,
        outputAspectHeight: Int,
        sourceRect: CGRect
    ) -> CanvasPlan? {
        guard outputAspectWidth > 0, outputAspectHeight > 0 else { return nil }
        guard sourceRect.width > 0, sourceRect.height > 0 else { return nil }
        let aspect = Double(outputAspectWidth) / Double(outputAspectHeight)
        let chosen = providerCanvasSizes.min { lhs, rhs in
            abs(log(aspect) - log(Double(lhs.width) / Double(lhs.height)))
                < abs(log(aspect) - log(Double(rhs.width) / Double(rhs.height)))
        } ?? providerCanvasSizes[0]
        let canvasWidth = CGFloat(chosen.width)
        let canvasHeight = CGFloat(chosen.height)
        let canvasAspect = Double(canvasWidth) / Double(canvasHeight)
        let finalFrame: CGRect
        if canvasAspect > aspect {
            let width = (canvasHeight * CGFloat(aspect)).rounded()
            finalFrame = CGRect(x: (canvasWidth - width) / 2, y: 0, width: width, height: canvasHeight)
        } else if canvasAspect < aspect {
            let height = (canvasWidth / CGFloat(aspect)).rounded()
            finalFrame = CGRect(x: 0, y: (canvasHeight - height) / 2, width: canvasWidth, height: height)
        } else {
            finalFrame = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        }
        return CanvasPlan(
            canvasWidth: chosen.width,
            canvasHeight: chosen.height,
            finalFrame: finalFrame,
            sourceDrawRect: pixelRect(sourceRect, in: finalFrame)
        )
    }

    static func providerGeometry(for plan: CanvasPlan) -> ProviderGeometry {
        ProviderGeometry(
            canvasWidth: plan.canvasWidth,
            canvasHeight: plan.canvasHeight,
            sourceRegion: CGRect(
                x: plan.sourceDrawRect.minX,
                y: CGFloat(plan.canvasHeight) - plan.sourceDrawRect.maxY,
                width: plan.sourceDrawRect.width,
                height: plan.sourceDrawRect.height
            )
        )
    }

    /// Maps a top-left-normalized rect into a CG (bottom-left origin) container.
    static func pixelRect(_ normalizedRect: CGRect, in container: CGRect) -> CGRect {
        CGRect(
            x: container.minX + normalizedRect.minX * container.width,
            y: container.minY + (1 - normalizedRect.maxY) * container.height,
            width: normalizedRect.width * container.width,
            height: normalizedRect.height * container.height
        )
    }

    /// The request's source region scaled into the generated image's own
    /// pixel space (top-left origin), for providers that return the requested
    /// canvas proportionally resized.
    static func scaledSourceRegion(
        generatedWidth: Int,
        generatedHeight: Int,
        geometry: ProviderGeometry
    ) -> CGRect? {
        guard generatedWidth > 0, generatedHeight > 0,
              geometry.canvasWidth > 0, geometry.canvasHeight > 0,
              geometry.sourceRegion.width > 0, geometry.sourceRegion.height > 0 else {
            return nil
        }
        let canvasScaleX = CGFloat(generatedWidth) / CGFloat(geometry.canvasWidth)
        let canvasScaleY = CGFloat(generatedHeight) / CGFloat(geometry.canvasHeight)
        return CGRect(
            x: geometry.sourceRegion.minX * canvasScaleX,
            y: geometry.sourceRegion.minY * canvasScaleY,
            width: geometry.sourceRegion.width * canvasScaleX,
            height: geometry.sourceRegion.height * canvasScaleY
        )
    }

    /// The CG-space rect at which to draw the provider result so that its
    /// source region lands exactly on `sourceTargetRect` in the output canvas,
    /// or nil when the result cannot be trusted to map proportionally (caller
    /// falls back to aspect-fill).
    static func alignedDrawRect(
        generatedWidth: Int,
        generatedHeight: Int,
        geometry: ProviderGeometry,
        sourceTargetRect: CGRect,
        outputWidth: Int,
        outputHeight: Int
    ) -> CGRect? {
        guard sourceTargetRect.width > 0, sourceTargetRect.height > 0,
              outputWidth > 0, outputHeight > 0,
              let region = scaledSourceRegion(
                  generatedWidth: generatedWidth,
                  generatedHeight: generatedHeight,
                  geometry: geometry
              ) else {
            return nil
        }
        // Providers may return a proportionally resized canvas, never a
        // re-framed one; a changed aspect means the request geometry no
        // longer describes the result.
        let canvasScaleX = CGFloat(generatedWidth) / CGFloat(geometry.canvasWidth)
        let canvasScaleY = CGFloat(generatedHeight) / CGFloat(geometry.canvasHeight)
        guard abs(canvasScaleX / canvasScaleY - 1) <= 0.05 else { return nil }
        // Top-left request coordinates → CG coordinates of the generated image.
        let regionCG = CGRect(
            x: region.minX,
            y: CGFloat(generatedHeight) - region.maxY,
            width: region.width,
            height: region.height
        )
        let scaleX = sourceTargetRect.width / regionCG.width
        let scaleY = sourceTargetRect.height / regionCG.height
        guard scaleX.isFinite, scaleY.isFinite,
              scaleX > 0.05, scaleX < 20, scaleY > 0.05, scaleY < 20,
              abs(scaleX / scaleY - 1) <= 0.05 else {
            return nil
        }
        let drawRect = CGRect(
            x: sourceTargetRect.minX - regionCG.minX * scaleX,
            y: sourceTargetRect.minY - regionCG.minY * scaleY,
            width: CGFloat(generatedWidth) * scaleX,
            height: CGFloat(generatedHeight) * scaleY
        )
        // The mapped result must cover the whole output frame (1px tolerance
        // for provider rounding); a gap means the geometry does not describe
        // this result and compositing it would leave unpainted output.
        let output = CGRect(x: 0, y: 0, width: CGFloat(outputWidth), height: CGFloat(outputHeight))
        guard drawRect.insetBy(dx: -1, dy: -1).contains(output) else { return nil }
        return drawRect
    }
}

/// Fixed provider-boundary prompt fragments for Zoom Out. These live at the
/// client boundary — not in the editable templates — so the guidance survives
/// operator edits to the prompt body.
enum LensZoomOutPrompt {
    /// Positive-form continuation frame prepended to every OpenAI zoom-out
    /// edit. gpt-image follows instructions, but negations read as content
    /// vocabulary, so subject singularity is stated affirmatively.
    static let openAIScenePreamble = """
    Zoom out: keep the supplied picture exactly as it is and fill the transparent area with more of the same place, continuing its perspective, lighting, palette, and rendering style. Every person, creature, and distinct object in this scene is already inside the supplied picture, so the new area shows only the surrounding scenery.
    """

    static func openAIWirePrompt(operatorPrompt: String) -> String {
        let trimmed = operatorPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? openAIScenePreamble : openAIScenePreamble + "\n\n" + trimmed
    }
}
