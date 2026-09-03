import AppKit
import Foundation

/// THE CONVENTION LAW: the viewpoint camera map is a DIAGRAM of stated
/// intent, never a measurement — `LensReframeSpec` carries no camera model,
/// depth, or world headings, so the plan view is a convention the image
/// itself legends:
/// - camera **A** (the original render's camera) sits at the bottom of the
///   plan looking "into" the scene, its wedge spanning the frame rectangle;
/// - the frame rectangle is the source frame's content footprint;
/// - vantage **B** is placed by mapping the reticle's `centerX` to lateral
///   position and `centerY` to depth (HIGHER in the source frame = FARTHER
///   from A);
/// - B's arrow is the 8-way `viewDirection` restated in plan space
///   (north = deeper into the scene, south = back toward A);
/// - reticle roll is deliberately omitted — image-plane roll has no
///   plan-view meaning; `{{focus_rotation_clause}}` already carries it.
///
/// Geometry is pure and unit-tested (`RosterCompositeSheet.layout`
/// precedent); drawing is a flipped `NSImage` handler (the
/// `RenderReferenceComposite.renderJPEG` technique).
struct LensViewpointSchematicPlan: Equatable {
    var canvasSize: CGSize
    var frameRect: CGRect
    var cameraA: CGPoint
    /// A's view of the frame: two sightlines from A to the frame's near
    /// corners (the "wedge").
    var wedgeLeft: CGPoint
    var wedgeRight: CGPoint
    var vantageB: CGPoint
    /// Unit vector in the FLIPPED canvas space (y grows downward, so
    /// "deeper into the scene" is negative y).
    var headingVector: CGVector
    var headingArrowEnd: CGPoint
    var legend: [String]
}

/// The 8-way image-plane direction restated as a plan-space unit vector in
/// flipped canvas coordinates. North ("toward the top of the source frame")
/// reads as deeper into the scene = up the plan.
func lensViewpointPlanHeading(_ direction: LensReframeViewDirection) -> CGVector {
    let diagonal = 1.0 / 2.0.squareRoot()
    switch direction {
    case .north: return CGVector(dx: 0, dy: -1)
    case .northeast: return CGVector(dx: diagonal, dy: -diagonal)
    case .east: return CGVector(dx: 1, dy: 0)
    case .southeast: return CGVector(dx: diagonal, dy: diagonal)
    case .south: return CGVector(dx: 0, dy: 1)
    case .southwest: return CGVector(dx: -diagonal, dy: diagonal)
    case .west: return CGVector(dx: -1, dy: 0)
    case .northwest: return CGVector(dx: -diagonal, dy: -diagonal)
    }
}

func lensViewpointSchematicPlan(spec: LensReframeSpec) -> LensViewpointSchematicPlan {
    let clean = spec.normalized()
    let canvas = CGSize(width: 1024, height: 1024)
    // Frame footprint: far edge at the top, near edge toward camera A.
    let frameRect = CGRect(x: 132, y: 132, width: 760, height: 520)
    let cameraA = CGPoint(x: canvas.width / 2, y: 930)
    let vantageB = CGPoint(
        x: frameRect.minX + CGFloat(clean.centerX) * frameRect.width,
        y: frameRect.minY + CGFloat(clean.centerY) * frameRect.height
    )
    let heading = lensViewpointPlanHeading(clean.resolvedViewDirection)
    let arrowLength: CGFloat = 120
    let legend = [
        "TOP-DOWN CAMERA MAP — schematic convention, not a rendering of the scene.",
        "A = the original camera, looking into the scene; rectangle = the source frame's content.",
        "B = the requested new vantage point. Arrow = B's look direction.",
        "Depth is stated intent: higher in the source frame = farther from A."
    ]
    return LensViewpointSchematicPlan(
        canvasSize: canvas,
        frameRect: frameRect,
        cameraA: cameraA,
        wedgeLeft: CGPoint(x: frameRect.minX, y: frameRect.maxY),
        wedgeRight: CGPoint(x: frameRect.maxX, y: frameRect.maxY),
        vantageB: vantageB,
        headingVector: heading,
        headingArrowEnd: CGPoint(
            x: vantageB.x + heading.dx * arrowLength,
            y: vantageB.y + heading.dy * arrowLength
        ),
        legend: legend
    )
}

/// Draws the plan as a PNG. Dark canvas matching the reframe composite's
/// palette so a third composite panel reads as part of the same instrument.
@MainActor
func renderLensViewpointSchematicPNG(plan: LensViewpointSchematicPlan) -> Data? {
    let ink = NSColor(calibratedWhite: 0.92, alpha: 1)
    let faint = NSColor(calibratedWhite: 0.55, alpha: 1)
    let brass = NSColor(calibratedRed: 0.79, green: 0.62, blue: 0.28, alpha: 1)
    let image = NSImage(size: plan.canvasSize, flipped: true) { _ in
        NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: plan.canvasSize)).fill()

        // The frame footprint.
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSBezierPath(rect: plan.frameRect).fill()
        faint.setStroke()
        let frameOutline = NSBezierPath(rect: plan.frameRect)
        frameOutline.lineWidth = 2
        frameOutline.stroke()

        // A's sightlines (dashed wedge).
        let wedge = NSBezierPath()
        wedge.move(to: plan.wedgeLeft)
        wedge.line(to: plan.cameraA)
        wedge.line(to: plan.wedgeRight)
        wedge.lineWidth = 2
        wedge.setLineDash([8, 6], count: 2, phase: 0)
        faint.setStroke()
        wedge.stroke()

        func label(_ text: String, at point: CGPoint, color: NSColor, size: CGFloat) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .bold),
                .foregroundColor: color
            ]
            NSAttributedString(string: text, attributes: attributes).draw(at: point)
        }

        // Camera A.
        ink.setFill()
        NSBezierPath(ovalIn: CGRect(x: plan.cameraA.x - 14, y: plan.cameraA.y - 14, width: 28, height: 28)).fill()
        label("A", at: CGPoint(x: plan.cameraA.x - 9, y: plan.cameraA.y + 22), color: ink, size: 30)
        label(
            "ORIGINAL CAMERA",
            at: CGPoint(x: plan.cameraA.x + 30, y: plan.cameraA.y - 12),
            color: faint,
            size: 20
        )

        // Vantage B: brass ring + heading arrow.
        brass.setStroke()
        let ring = NSBezierPath(ovalIn: CGRect(x: plan.vantageB.x - 14, y: plan.vantageB.y - 14, width: 28, height: 28))
        ring.lineWidth = 4
        ring.stroke()
        label("B", at: CGPoint(x: plan.vantageB.x + 20, y: plan.vantageB.y - 38), color: brass, size: 30)

        let arrow = NSBezierPath()
        arrow.move(to: plan.vantageB)
        arrow.line(to: plan.headingArrowEnd)
        arrow.lineWidth = 5
        brass.setStroke()
        arrow.stroke()
        // Arrowhead: two short strokes back from the tip.
        let tip = plan.headingArrowEnd
        let back = CGVector(dx: -plan.headingVector.dx, dy: -plan.headingVector.dy)
        let perp = CGVector(dx: -plan.headingVector.dy, dy: plan.headingVector.dx)
        let headLength: CGFloat = 22
        let headWidth: CGFloat = 12
        let head = NSBezierPath()
        head.move(to: CGPoint(
            x: tip.x + back.dx * headLength + perp.dx * headWidth,
            y: tip.y + back.dy * headLength + perp.dy * headWidth
        ))
        head.line(to: tip)
        head.line(to: CGPoint(
            x: tip.x + back.dx * headLength - perp.dx * headWidth,
            y: tip.y + back.dy * headLength - perp.dy * headWidth
        ))
        head.lineWidth = 5
        head.stroke()

        // Legend block at the bottom.
        var legendY = plan.canvasSize.height - CGFloat(plan.legend.count) * 26 - 14
        for (index, line) in plan.legend.enumerated() {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 17, weight: index == 0 ? .bold : .regular),
                .foregroundColor: index == 0 ? ink : faint
            ]
            NSAttributedString(string: line, attributes: attributes)
                .draw(at: CGPoint(x: 24, y: legendY))
            legendY += 26
        }
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        return nil
    }
    return png
}
