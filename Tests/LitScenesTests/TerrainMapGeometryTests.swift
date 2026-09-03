import CoreGraphics
import Foundation
import Testing
@testable import LitScenes

// The terrain growth law: directions are pure (an eastward pass adds terrain
// only on the east edge), the cap refuses rather than downsamples, and pin
// remaps compose exactly across chained passes.

@Test func growthPlanEastGrowsOnlyEast() throws {
    let plan = TerrainMapGeometry.growthPlan(
        canvasWidth: 1024, canvasHeight: 1024, direction: .east, scale: 0.7
    )
    let unwrapped = try #require(plan)
    #expect(unwrapped.newCanvasWidth == 1463)
    #expect(unwrapped.newCanvasHeight == 1024)
    #expect(unwrapped.priorContentRect.minX == 0)
    #expect(unwrapped.priorContentRect.minY == 0)
    #expect(abs(unwrapped.priorContentRect.width - 1024.0 / 1463.0) < 0.0001)
    #expect(unwrapped.priorContentRect.height == 1)
}

@Test func growthPlanPerDirectionPlacesPriorContent() {
    func rect(_ direction: TerrainGrowthDirection) -> CGRect {
        TerrainMapGeometry.growthPlan(
            canvasWidth: 1000, canvasHeight: 800, direction: direction, scale: 0.7
        )!.priorContentRect
    }
    // West growth keeps the old content on the east edge.
    let west = rect(.west)
    #expect(abs(west.maxX - 1) < 0.0001)
    #expect(west.height == 1)
    // North growth (new terrain at the top) anchors old content at the bottom.
    let north = rect(.north)
    #expect(abs(north.maxY - 1) < 0.0001)
    #expect(north.width == 1)
    let south = rect(.south)
    #expect(south.minY == 0)
    // Radial centers it.
    let radial = rect(.radial)
    #expect(abs(radial.midX - 0.5) < 0.0001)
    #expect(abs(radial.midY - 0.5) < 0.0001)
}

@Test func growthPlanClampsScaleToOutpaintFloor() {
    // A scale below the per-pass floor clamps up to 0.60 rather than
    // inventing more than a provider continues coherently.
    let plan = TerrainMapGeometry.growthPlan(
        canvasWidth: 1200, canvasHeight: 1200, direction: .east, scale: 0.3
    )!
    #expect(plan.newCanvasWidth == 2000)
    // And above the ceiling clamps down to 0.85.
    let gentle = TerrainMapGeometry.growthPlan(
        canvasWidth: 1700, canvasHeight: 1700, direction: .east, scale: 0.99
    )!
    #expect(gentle.newCanvasWidth == 2000)
}

@Test func growthPlanRefusesPastCanvasCap() {
    // 3000/0.7 ≈ 4286 > 4096: refuse, never downsample.
    #expect(TerrainMapGeometry.growthPlan(
        canvasWidth: 3000, canvasHeight: 1024, direction: .east, scale: 0.7
    ) == nil)
    // The un-grown axis may already sit at the cap.
    #expect(TerrainMapGeometry.growthPlan(
        canvasWidth: 1024, canvasHeight: 4096, direction: .east, scale: 0.7
    ) != nil)
    #expect(TerrainMapGeometry.growthPlan(
        canvasWidth: 1024, canvasHeight: 4096, direction: .north, scale: 0.7
    ) == nil)
}

@Test func pinRemapComposesAcrossChainedGrowths() {
    let pin = TerrainMapPin(placeId: "place_a", x: 0.25, y: 0.75, regionWidth: 0.2, regionHeight: 0.2)
    let first = TerrainMapGeometry.growthPlan(
        canvasWidth: 1024, canvasHeight: 1024, direction: .east, scale: 0.7
    )!
    let second = TerrainMapGeometry.growthPlan(
        canvasWidth: first.newCanvasWidth, canvasHeight: first.newCanvasHeight, direction: .north, scale: 0.7
    )!
    let stepped = TerrainMapGeometry.remappedPin(
        TerrainMapGeometry.remappedPin(pin, throughPriorContentRect: first.priorContentRect),
        throughPriorContentRect: second.priorContentRect
    )
    // Composing the rects and remapping once names the same world point.
    let r1 = first.priorContentRect
    let r2 = second.priorContentRect
    let composed = CGRect(
        x: r2.minX + r1.minX * r2.width,
        y: r2.minY + r1.minY * r2.height,
        width: r1.width * r2.width,
        height: r1.height * r2.height
    )
    let direct = TerrainMapGeometry.remappedPin(pin, throughPriorContentRect: composed)
    #expect(abs(stepped.x - direct.x) < 0.000001)
    #expect(abs(stepped.y - direct.y) < 0.000001)
    #expect(abs(stepped.regionWidth - direct.regionWidth) < 0.000001)
    #expect(abs(stepped.regionHeight - direct.regionHeight) < 0.000001)
}

@Test func regionPixelRectClampsInsideCanvas() {
    let corner = TerrainMapPin(placeId: "p", x: 0.02, y: 0.98, regionWidth: 0.3, regionHeight: 0.3)
    let rect = TerrainMapGeometry.regionPixelRect(pin: corner, canvasWidth: 1000, canvasHeight: 1000)!
    #expect(rect.minX >= 0)
    #expect(rect.maxY <= 1000)
    #expect(rect.minY >= 0)
    #expect(abs(rect.width - 300) <= 1)
    #expect(abs(rect.height - 300) <= 1)
    #expect(rect == rect.integral)
}

@Test func providerPlanPicksCanvasNearGrownAspect() {
    // 1024² grown east → 1463×1024 (aspect ≈ 1.43) plans on the 1536×1024
    // provider canvas with a final frame of the grown aspect.
    let plan = TerrainMapGeometry.growthPlan(
        canvasWidth: 1024, canvasHeight: 1024, direction: .east, scale: 0.7
    )!
    #expect(plan.providerPlan.canvasWidth == 1536)
    #expect(plan.providerPlan.canvasHeight == 1024)
    let frame = plan.providerPlan.finalFrame
    let frameAspect = Double(frame.width) / Double(frame.height)
    let grownAspect = Double(plan.newCanvasWidth) / Double(plan.newCanvasHeight)
    #expect(abs(frameAspect - grownAspect) < 0.01)
    // The source lands on the west side of the frame, full height.
    #expect(abs(plan.providerPlan.sourceDrawRect.minX - frame.minX) < 0.5)
    #expect(abs(plan.providerPlan.sourceDrawRect.height - frame.height) < 0.5)
}

@Test func zoomOutSpecPathStillMatchesRectOverload() {
    // The extracted rect-based planner is the same law the spec path used:
    // both answers agree for a zoom-out spec.
    let spec = LensReframeSpec(
        mode: LensReframeSpec.zoomOutMode,
        centerX: 0.4,
        centerY: 0.6,
        normalizedWidth: 0.7,
        normalizedHeight: 0.7
    )
    let viaSpec = LensZoomOutGeometry.canvasPlan(sourceWidth: 1600, sourceHeight: 900, spec: spec)
    let viaRect = LensZoomOutGeometry.canvasPlan(
        outputAspectWidth: 1600,
        outputAspectHeight: 900,
        sourceRect: LensZoomOutGeometry.normalizedSourceRect(spec)
    )
    #expect(viaSpec == viaRect)
    #expect(viaSpec != nil)
}

@Test func stampFeatherEdgesFollowGrowthDirection() {
    let east = TerrainMapGeometry.growthPlan(
        canvasWidth: 1024, canvasHeight: 1024, direction: .east, scale: 0.7
    )!
    let eastEdges = TerrainMapGeometry.stampFeatherEdges(priorContentRect: east.priorContentRect)
    #expect(eastEdges == TerrainStampFeatherEdges(top: false, bottom: false, left: false, right: true))
    let radial = TerrainMapGeometry.growthPlan(
        canvasWidth: 1024, canvasHeight: 1024, direction: .radial, scale: 0.7
    )!
    let radialEdges = TerrainMapGeometry.stampFeatherEdges(priorContentRect: radial.priorContentRect)
    #expect(radialEdges == TerrainStampFeatherEdges(top: true, bottom: true, left: true, right: true))
}

@Test func stampFeatherWidthClampsForSmallStamps() {
    #expect(TerrainMapGeometry.stampFeatherWidth(stampSize: CGSize(width: 1024, height: 1024)) == 16)
    #expect(TerrainMapGeometry.stampFeatherWidth(stampSize: CGSize(width: 40, height: 1024)) == 10)
}
