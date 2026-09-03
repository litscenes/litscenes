import AppKit
import Foundation
import Testing
@testable import LitScenes

// THE CONVENTION LAW's firewall: the camera-map plan is pure, monotonic, and
// clamped, the 8-way compass restates as distinct unit headings, and the
// renderer produces a real PNG at the planned size.

@Test func viewpointPlanMappingIsMonotonicAndClamped() {
    func plan(_ x: Double, _ y: Double) -> LensViewpointSchematicPlan {
        lensViewpointSchematicPlan(spec: LensReframeSpec(
            mode: LensReframeSpec.viewpointMode,
            centerX: x,
            centerY: y
        ))
    }
    let left = plan(0, 0.5)
    let mid = plan(0.5, 0.5)
    let right = plan(1, 0.5)
    #expect(left.vantageB.x == left.frameRect.minX)
    #expect(abs(mid.vantageB.x - mid.frameRect.midX) < 0.001)
    #expect(right.vantageB.x == right.frameRect.maxX)
    #expect(left.vantageB.x < mid.vantageB.x)
    #expect(mid.vantageB.x < right.vantageB.x)

    // Depth: higher in the source frame (smaller centerY) = farther from A
    // = smaller plan y (the far edge is the rect's top in flipped space).
    let far = plan(0.5, 0)
    let near = plan(0.5, 1)
    #expect(far.vantageB.y == far.frameRect.minY)
    #expect(near.vantageB.y == near.frameRect.maxY)
    #expect(far.vantageB.y < near.vantageB.y)
    #expect(near.vantageB.y < near.cameraA.y)

    // Out-of-range input clamps through the spec's own normalize.
    let clamped = plan(4, -3)
    #expect(clamped.vantageB.x == clamped.frameRect.maxX)
    #expect(clamped.vantageB.y == clamped.frameRect.minY)
}

@Test func allEightCompassDirectionsYieldDistinctUnitHeadings() {
    var seen: Set<String> = []
    for direction in LensReframeViewDirection.allCases {
        let heading = lensViewpointPlanHeading(direction)
        let magnitude = (heading.dx * heading.dx + heading.dy * heading.dy).squareRoot()
        #expect(abs(magnitude - 1) < 0.001)
        seen.insert(String(format: "%.3f|%.3f", heading.dx, heading.dy))
    }
    #expect(seen.count == LensReframeViewDirection.allCases.count)

    // The plan-space restatement: north = deeper into the scene (up the
    // flipped canvas), south = back toward camera A.
    #expect(lensViewpointPlanHeading(.north).dy < 0)
    #expect(lensViewpointPlanHeading(.south).dy > 0)
    #expect(lensViewpointPlanHeading(.east).dx > 0)
    #expect(lensViewpointPlanHeading(.west).dx < 0)
}

@Test func degenerateSpecPlansCenteredWithLegendAndArrow() {
    let plan = lensViewpointSchematicPlan(spec: LensReframeSpec(mode: LensReframeSpec.viewpointMode))
    #expect(abs(plan.vantageB.x - plan.frameRect.midX) < 0.001)
    #expect(abs(plan.vantageB.y - plan.frameRect.midY) < 0.001)
    #expect(plan.canvasSize == CGSize(width: 1024, height: 1024))
    #expect(!plan.legend.isEmpty)
    // Default north heading: the arrow ends deeper into the scene than B.
    #expect(plan.headingArrowEnd.y < plan.vantageB.y)
    // Camera A sits below the frame footprint, wedge spanning its near edge.
    #expect(plan.cameraA.y > plan.frameRect.maxY)
    #expect(plan.wedgeLeft == CGPoint(x: plan.frameRect.minX, y: plan.frameRect.maxY))
    #expect(plan.wedgeRight == CGPoint(x: plan.frameRect.maxX, y: plan.frameRect.maxY))
}

@MainActor
@Test func schematicPNGRendersNonEmptyAtPlannedSize() {
    let plan = lensViewpointSchematicPlan(spec: LensReframeSpec(
        mode: LensReframeSpec.viewpointMode,
        centerX: 0.3,
        centerY: 0.7,
        viewDirection: LensReframeViewDirection.southeast.rawValue
    ))
    guard let data = renderLensViewpointSchematicPNG(plan: plan) else {
        Issue.record("Schematic PNG failed to render")
        return
    }
    #expect(!data.isEmpty)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        Issue.record("Schematic PNG did not decode")
        return
    }
    #expect(bitmap.pixelsWide == Int(plan.canvasSize.width))
    #expect(bitmap.pixelsHigh == Int(plan.canvasSize.height))
}

@Test func includeCameraMapDecodesAbsentAsTrueAndRoundTrips() throws {
    // Pre-field spec blobs decode with the map ON — the tolerant law.
    let legacy = #"{"mode": "viewpoint", "centerX": 0.4, "centerY": 0.6}"#
    let decoded = try JSONDecoder().decode(LensReframeSpec.self, from: Data(legacy.utf8))
    #expect(decoded.includeCameraMap)

    var disabled = decoded
    disabled.includeCameraMap = false
    let round = try JSONDecoder().decode(
        LensReframeSpec.self,
        from: JSONEncoder().encode(disabled)
    )
    #expect(!round.includeCameraMap)
    #expect(round == disabled.normalized())
}
