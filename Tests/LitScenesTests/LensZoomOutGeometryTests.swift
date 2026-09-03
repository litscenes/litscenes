import CoreGraphics
import Foundation
import Testing
@testable import LitScenes

private func zoomOutSpec(
    centerX: Double = 0.5,
    centerY: Double = 0.5,
    scale: Double = 0.35
) -> LensReframeSpec {
    LensReframeSpec(
        mode: LensReframeSpec.zoomOutMode,
        centerX: centerX,
        centerY: centerY,
        normalizedWidth: scale,
        normalizedHeight: scale
    ).normalized()
}

/// Where the request's source region lands after drawing the generated image
/// at `drawRect` — the invariant alignedDrawRect must satisfy.
private func mappedSourceRegion(
    drawRect: CGRect,
    generatedWidth: Int,
    generatedHeight: Int,
    geometry: LensZoomOutGeometry.ProviderGeometry
) -> CGRect {
    let canvasScaleX = CGFloat(generatedWidth) / CGFloat(geometry.canvasWidth)
    let canvasScaleY = CGFloat(generatedHeight) / CGFloat(geometry.canvasHeight)
    let region = CGRect(
        x: geometry.sourceRegion.minX * canvasScaleX,
        y: geometry.sourceRegion.minY * canvasScaleY,
        width: geometry.sourceRegion.width * canvasScaleX,
        height: geometry.sourceRegion.height * canvasScaleY
    )
    let scaleX = drawRect.width / CGFloat(generatedWidth)
    let scaleY = drawRect.height / CGFloat(generatedHeight)
    return CGRect(
        x: drawRect.minX + region.minX * scaleX,
        y: drawRect.minY + (CGFloat(generatedHeight) - region.maxY) * scaleY,
        width: region.width * scaleX,
        height: region.height * scaleY
    )
}

private func expectClose(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) {
    #expect(abs(lhs.minX - rhs.minX) <= tolerance)
    #expect(abs(lhs.minY - rhs.minY) <= tolerance)
    #expect(abs(lhs.width - rhs.width) <= tolerance)
    #expect(abs(lhs.height - rhs.height) <= tolerance)
}

@Test func zoomOutCanvasPlanPicksProviderLandscapeCanvasFor16x9Sources() {
    guard let plan = LensZoomOutGeometry.canvasPlan(
        sourceWidth: 1024,
        sourceHeight: 576,
        spec: zoomOutSpec()
    ) else {
        Issue.record("missing canvas plan")
        return
    }
    #expect(plan.sizeString == "1536x1024")
    #expect(plan.finalFrame == CGRect(x: 0, y: 80, width: 1536, height: 864))
    // 35% of the final frame, centered, keeping the source aspect exactly.
    #expect(abs(plan.sourceDrawRect.width - 537.6) < 0.5)
    #expect(abs(plan.sourceDrawRect.height - 302.4) < 0.5)
    #expect(abs(plan.sourceDrawRect.midX - 768) < 0.5)
    #expect(abs(plan.sourceDrawRect.midY - 512) < 0.5)
    #expect(abs(plan.sourceDrawRect.width / plan.sourceDrawRect.height - 1024.0 / 576.0) < 0.001)
}

@Test func zoomOutCanvasPlanMatchesPortraitSquareAndNativeAspects() {
    let portrait = LensZoomOutGeometry.canvasPlan(sourceWidth: 576, sourceHeight: 1024, spec: zoomOutSpec())
    #expect(portrait?.sizeString == "1024x1536")
    #expect(portrait?.finalFrame == CGRect(x: 80, y: 0, width: 864, height: 1536))

    let square = LensZoomOutGeometry.canvasPlan(sourceWidth: 800, sourceHeight: 800, spec: zoomOutSpec())
    #expect(square?.sizeString == "1024x1024")
    #expect(square?.finalFrame == CGRect(x: 0, y: 0, width: 1024, height: 1024))

    let native = LensZoomOutGeometry.canvasPlan(sourceWidth: 1536, sourceHeight: 1024, spec: zoomOutSpec())
    #expect(native?.sizeString == "1536x1024")
    #expect(native?.finalFrame == CGRect(x: 0, y: 0, width: 1536, height: 1024))
}

@Test func zoomOutGeometryClampsExtremePlacementsInsideTheFrame() {
    // Raising the scale after an edge placement can push the raw spec rect out
    // of the unit frame; every geometry consumer shares the clamped answer.
    let spec = zoomOutSpec(centerX: 0.02, centerY: 0.97, scale: 0.10)
    let rect = LensZoomOutGeometry.normalizedSourceRect(spec)
    #expect(rect.minX >= 0)
    #expect(rect.maxY <= 1)
    #expect(abs(rect.width - 0.10) < 0.0001)

    guard let plan = LensZoomOutGeometry.canvasPlan(sourceWidth: 1024, sourceHeight: 576, spec: spec) else {
        Issue.record("missing canvas plan")
        return
    }
    #expect(plan.finalFrame.insetBy(dx: -0.001, dy: -0.001).contains(plan.sourceDrawRect))
    // A left-edge placement lands on the final frame's left edge.
    #expect(abs(plan.sourceDrawRect.minX - plan.finalFrame.minX) < 0.5)
}

@Test func alignedDrawRectMapsProviderOutputOntoTheSourceTargetRect() {
    let spec = zoomOutSpec()
    guard let plan = LensZoomOutGeometry.canvasPlan(sourceWidth: 1024, sourceHeight: 576, spec: spec) else {
        Issue.record("missing canvas plan")
        return
    }
    let geometry = LensZoomOutGeometry.providerGeometry(for: plan)
    let sourceTargetRect = LensZoomOutGeometry.pixelRect(
        LensZoomOutGeometry.normalizedSourceRect(spec),
        in: CGRect(x: 0, y: 0, width: 1024, height: 576)
    )

    guard let drawRect = LensZoomOutGeometry.alignedDrawRect(
        generatedWidth: 1536,
        generatedHeight: 1024,
        geometry: geometry,
        sourceTargetRect: sourceTargetRect,
        outputWidth: 1024,
        outputHeight: 576
    ) else {
        Issue.record("expected an aligned mapping at the planned size")
        return
    }
    expectClose(
        mappedSourceRegion(drawRect: drawRect, generatedWidth: 1536, generatedHeight: 1024, geometry: geometry),
        sourceTargetRect,
        tolerance: 0.01
    )
    // The width maps edge-to-edge; the out-of-frame bands overflow vertically
    // and crop away.
    #expect(abs(drawRect.minX) < 0.01)
    #expect(abs(drawRect.width - 1024) < 0.01)
    #expect(drawRect.minY < 0)
    #expect(drawRect.maxY > 576)

    // A proportionally downscaled result still maps exactly.
    if let half = LensZoomOutGeometry.alignedDrawRect(
        generatedWidth: 768,
        generatedHeight: 512,
        geometry: geometry,
        sourceTargetRect: sourceTargetRect,
        outputWidth: 1024,
        outputHeight: 576
    ) {
        expectClose(
            mappedSourceRegion(drawRect: half, generatedWidth: 768, generatedHeight: 512, geometry: geometry),
            sourceTargetRect,
            tolerance: 0.01
        )
    } else {
        Issue.record("expected an aligned mapping for a proportional resize")
    }

    // A re-framed aspect cannot be trusted; the caller must aspect-fill.
    #expect(LensZoomOutGeometry.alignedDrawRect(
        generatedWidth: 1024,
        generatedHeight: 1024,
        geometry: geometry,
        sourceTargetRect: sourceTargetRect,
        outputWidth: 1024,
        outputHeight: 576
    ) == nil)
}

@Test func alignedDrawRectHandlesTheTracedFALOutpaintFixture() {
    // Trace lens_hero_19de3fd9968198: 428x241 source, expansions L97/R698/T409/B39,
    // provider returned 1216x688 for the 1223x689 request.
    let geometry = LensZoomOutGeometry.ProviderGeometry(
        canvasWidth: 1223,
        canvasHeight: 689,
        sourceRegion: CGRect(x: 97, y: 409, width: 428, height: 241)
    )
    let normalized = CGRect(
        x: 97.0 / 1223.0,
        y: 409.0 / 689.0,
        width: 428.0 / 1223.0,
        height: 241.0 / 689.0
    )
    let sourceTargetRect = LensZoomOutGeometry.pixelRect(normalized, in: CGRect(x: 0, y: 0, width: 1024, height: 576))

    guard let drawRect = LensZoomOutGeometry.alignedDrawRect(
        generatedWidth: 1216,
        generatedHeight: 688,
        geometry: geometry,
        sourceTargetRect: sourceTargetRect,
        outputWidth: 1024,
        outputHeight: 576
    ) else {
        Issue.record("expected an aligned mapping for the FAL fixture")
        return
    }
    expectClose(
        mappedSourceRegion(drawRect: drawRect, generatedWidth: 1216, generatedHeight: 688, geometry: geometry),
        sourceTargetRect,
        tolerance: 0.01
    )
    #expect(drawRect.insetBy(dx: -1, dy: -1).contains(CGRect(x: 0, y: 0, width: 1024, height: 576)))
}

@Test func zoomOutPassCountsMatchTheRatifiedRange() {
    #expect(LensZoomOutGeometry.zoomOutPassCount(totalScale: 0.75) == 1)
    #expect(LensZoomOutGeometry.zoomOutPassCount(totalScale: 0.60) == 1)
    #expect(LensZoomOutGeometry.zoomOutPassCount(totalScale: 0.55) == 2)
    #expect(LensZoomOutGeometry.zoomOutPassCount(totalScale: 0.40) == 2)
    #expect(LensZoomOutGeometry.zoomOutPassCount(totalScale: 0.35) == 3)
    // Legacy persisted extremes stay bounded by the pass cap.
    #expect(LensZoomOutGeometry.zoomOutPassCount(totalScale: 0.10) == 4)
}

@Test func zoomOutPassRectsComposeExactlyAndStayCapSafe() {
    // Corner placement (all horizontal margin on one side) and an asymmetric
    // placement both compose back to the clamped spec rect, and every pass
    // stays inside FAL's per-edge cap at a full-resolution 1024x576 source.
    let fixtures = [
        zoomOutSpec(centerX: 0.175, centerY: 0.825, scale: 0.35),
        zoomOutSpec(centerX: 0.6, centerY: 0.55, scale: 0.40),
        zoomOutSpec(centerX: 0.5, centerY: 0.5, scale: 0.55)
    ]
    for spec in fixtures {
        let total = LensZoomOutGeometry.normalizedSourceRect(spec)
        let passes = LensZoomOutGeometry.zoomOutPassRects(spec: spec)
        #expect(passes.count == LensZoomOutGeometry.zoomOutPassCount(totalScale: Double(total.width)))

        // Compose: accumulate the source rect through the chain.
        var accumulated = CGRect(x: 0, y: 0, width: 1, height: 1)
        for pass in passes {
            #expect(Double(pass.width) >= 0.594)
            accumulated = CGRect(
                x: pass.minX + accumulated.minX * pass.width,
                y: pass.minY + accumulated.minY * pass.height,
                width: accumulated.width * pass.width,
                height: accumulated.height * pass.height
            )
            // Cap safety: per-pass pixel expansions at a 1024x576 source.
            let left = Double(pass.minX) / Double(pass.width) * 1024
            let right = Double(1 - pass.maxX) / Double(pass.width) * 1024
            let top = Double(pass.minY) / Double(pass.height) * 576
            let bottom = Double(1 - pass.maxY) / Double(pass.height) * 576
            #expect(max(left, right, top, bottom) <= 699)
        }
        #expect(abs(accumulated.minX - total.minX) < 1e-9)
        #expect(abs(accumulated.minY - total.minY) < 1e-9)
        #expect(abs(accumulated.width - total.width) < 1e-9)
        #expect(abs(accumulated.height - total.height) < 1e-9)
    }

    // Single-pass scales return the spec rect untouched.
    let single = zoomOutSpec(scale: 0.75)
    #expect(LensZoomOutGeometry.zoomOutPassRects(spec: single) == [LensZoomOutGeometry.normalizedSourceRect(single)])
}

@Test func openAIZoomOutWirePromptLeadsWithPositiveContinuation() {
    let wire = LensZoomOutPrompt.openAIWirePrompt(operatorPrompt: "Original scene context: a chapel.")
    // The fixed frame rides at the client boundary so it survives operator
    // edits to the template body; phrased affirmatively — negations read as
    // content vocabulary.
    #expect(wire.hasPrefix("Zoom out: keep the supplied picture exactly as it is"))
    #expect(wire.contains("already inside the supplied picture"))
    #expect(wire.hasSuffix("a chapel."))
    #expect(!wire.lowercased().contains("never"))
    #expect(LensZoomOutPrompt.openAIWirePrompt(operatorPrompt: "  ") == LensZoomOutPrompt.openAIScenePreamble)
}

@Test func scaledSourceRegionTracksProportionalResizes() {
    let geometry = LensZoomOutGeometry.ProviderGeometry(
        canvasWidth: 1223,
        canvasHeight: 689,
        sourceRegion: CGRect(x: 97, y: 409, width: 428, height: 241)
    )
    guard let region = LensZoomOutGeometry.scaledSourceRegion(
        generatedWidth: 1216,
        generatedHeight: 688,
        geometry: geometry
    ) else {
        Issue.record("expected a scaled source region")
        return
    }
    #expect(abs(region.minX - 97.0 * 1216.0 / 1223.0) < 0.01)
    #expect(abs(region.minY - 409.0 * 688.0 / 689.0) < 0.01)
    #expect(abs(region.width - 428.0 * 1216.0 / 1223.0) < 0.01)
    #expect(LensZoomOutGeometry.scaledSourceRegion(generatedWidth: 0, generatedHeight: 688, geometry: geometry) == nil)
}

@Test func alignedDrawRectRespectsVerticalAsymmetry() {
    // Source near the TOP of the request canvas (top margin 50, bottom 650):
    // a forgotten Y-flip would land the mapping 300px away and fail coverage.
    let geometry = LensZoomOutGeometry.ProviderGeometry(
        canvasWidth: 1000,
        canvasHeight: 1000,
        sourceRegion: CGRect(x: 100, y: 50, width: 300, height: 300)
    )
    let sourceTargetRect = LensZoomOutGeometry.pixelRect(
        CGRect(x: 0.1, y: 0.05, width: 0.3, height: 0.3),
        in: CGRect(x: 0, y: 0, width: 500, height: 500)
    )
    guard let drawRect = LensZoomOutGeometry.alignedDrawRect(
        generatedWidth: 1000,
        generatedHeight: 1000,
        geometry: geometry,
        sourceTargetRect: sourceTargetRect,
        outputWidth: 500,
        outputHeight: 500
    ) else {
        Issue.record("expected an aligned mapping")
        return
    }
    expectClose(drawRect, CGRect(x: 0, y: 0, width: 500, height: 500), tolerance: 0.01)
    expectClose(
        mappedSourceRegion(drawRect: drawRect, generatedWidth: 1000, generatedHeight: 1000, geometry: geometry),
        sourceTargetRect,
        tolerance: 0.01
    )
}
