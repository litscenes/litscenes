import CoreGraphics
import Foundation

/// Which way a terrain growth pass extends the map. Directions are pure: an
/// eastward pass adds terrain only on the east edge. Radial grows all four
/// edges around the centered prior content.
enum TerrainGrowthDirection: String, CaseIterable, Identifiable, Sendable {
    case north
    case south
    case east
    case west
    case radial

    var id: String { rawValue }

    var label: String {
        switch self {
        case .north: return "North"
        case .south: return "South"
        case .east: return "East"
        case .west: return "West"
        case .radial: return "All around"
        }
    }
}

/// One planned growth pass: the new map canvas dimensions, where the existing
/// canvas's content lands in it (top-left normalized), and the provider-native
/// outpaint plan that fills the rest.
struct TerrainGrowthPlan: Equatable {
    var newCanvasWidth: Int
    var newCanvasHeight: Int
    /// Where the prior canvas sits inside the new canvas, top-left normalized.
    var priorContentRect: CGRect
    /// The provider-space canvas + mask placement, reusing the Zoom Out
    /// planner with the terrain rect (which, unlike zoom-out's, may be
    /// anisotropic — pure edge growth changes the canvas aspect).
    var providerPlan: LensZoomOutGeometry.CanvasPlan
}

/// Which edges of the re-stamped original border NEWLY GENERATED content (and
/// therefore need a feathered alpha falloff); edges on the canvas boundary
/// stay hard.
struct TerrainStampFeatherEdges: Equatable {
    var top = false
    var bottom = false
    var left = false
    var right = false
}

/// Pure geometry for the terrain map: growth planning, pin remapping, region
/// crops, and the stamp-feather arithmetic. Zero SwiftUI, zero engine — the
/// LensZoomOutGeometry / ExcursionModels split.
enum TerrainMapGeometry {

    /// Refuse-not-downsample canvas ceiling: a growth pass that would push the
    /// long edge past this returns no plan, and the caller states the cap.
    static let maxCanvasLongEdge = 4096
    /// The v1 growth control is one fixed knob: the prior content keeps 70%
    /// of the growth axis, comfortably above the outpaint floor.
    static let defaultGrowthScale = 0.7
    static let maximumGrowthScale = 0.85

    /// Feathered falloff width for the original-pixel re-stamp, in output
    /// canvas pixels (clamped down for small stamps).
    static let stampFeatherPixels: CGFloat = 16

    /// Plans one growth pass. `scale` is the fraction of the growth axis the
    /// prior content keeps, clamped to [minimumPerPassSourceScale, 0.85] so a
    /// single pass never invents more than providers continue coherently.
    /// Returns nil when the grown canvas would exceed `maxLongEdge`.
    static func growthPlan(
        canvasWidth: Int,
        canvasHeight: Int,
        direction: TerrainGrowthDirection,
        scale: Double = defaultGrowthScale,
        maxLongEdge: Int = maxCanvasLongEdge
    ) -> TerrainGrowthPlan? {
        guard canvasWidth > 0, canvasHeight > 0 else { return nil }
        let clamped = min(maximumGrowthScale, max(LensZoomOutGeometry.minimumPerPassSourceScale, scale))
        var newWidth = canvasWidth
        var newHeight = canvasHeight
        switch direction {
        case .east, .west:
            newWidth = Int((Double(canvasWidth) / clamped).rounded())
        case .north, .south:
            newHeight = Int((Double(canvasHeight) / clamped).rounded())
        case .radial:
            newWidth = Int((Double(canvasWidth) / clamped).rounded())
            newHeight = Int((Double(canvasHeight) / clamped).rounded())
        }
        guard max(newWidth, newHeight) <= maxLongEdge else { return nil }
        guard newWidth > canvasWidth || newHeight > canvasHeight else { return nil }
        let contentWidth = Double(canvasWidth) / Double(newWidth)
        let contentHeight = Double(canvasHeight) / Double(newHeight)
        let priorContentRect: CGRect
        switch direction {
        case .east:
            priorContentRect = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        case .west:
            priorContentRect = CGRect(x: 1 - contentWidth, y: 0, width: contentWidth, height: contentHeight)
        case .north:
            priorContentRect = CGRect(x: 0, y: 1 - contentHeight, width: contentWidth, height: contentHeight)
        case .south:
            priorContentRect = CGRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        case .radial:
            priorContentRect = CGRect(
                x: (1 - contentWidth) / 2,
                y: (1 - contentHeight) / 2,
                width: contentWidth,
                height: contentHeight
            )
        }
        guard let providerPlan = LensZoomOutGeometry.canvasPlan(
            outputAspectWidth: newWidth,
            outputAspectHeight: newHeight,
            sourceRect: priorContentRect
        ) else {
            return nil
        }
        return TerrainGrowthPlan(
            newCanvasWidth: newWidth,
            newCanvasHeight: newHeight,
            priorContentRect: priorContentRect,
            providerPlan: providerPlan
        )
    }

    /// Remaps a pin from the prior canvas's normalized space into the grown
    /// canvas's, through the growth pass's prior-content rect. Composing two
    /// growths' remaps equals remapping through the composed rect, so pins
    /// keep naming the same world point across any number of passes.
    static func remappedPin(_ pin: TerrainMapPin, throughPriorContentRect rect: CGRect) -> TerrainMapPin {
        guard rect.width > 0, rect.height > 0 else { return pin }
        var value = pin
        value.x = Double(rect.minX) + pin.x * Double(rect.width)
        value.y = Double(rect.minY) + pin.y * Double(rect.height)
        value.regionWidth = pin.regionWidth * Double(rect.width)
        value.regionHeight = pin.regionHeight * Double(rect.height)
        return value.normalized()
    }

    /// The pin's region as an integral pixel rect in the current canvas,
    /// clamped fully inside it (top-left origin).
    static func regionPixelRect(pin: TerrainMapPin, canvasWidth: Int, canvasHeight: Int) -> CGRect? {
        guard canvasWidth > 0, canvasHeight > 0 else { return nil }
        let width = min(CGFloat(canvasWidth), max(1, CGFloat(pin.regionWidth) * CGFloat(canvasWidth)))
        let height = min(CGFloat(canvasHeight), max(1, CGFloat(pin.regionHeight) * CGFloat(canvasHeight)))
        var x = CGFloat(pin.x) * CGFloat(canvasWidth) - width / 2
        var y = CGFloat(pin.y) * CGFloat(canvasHeight) - height / 2
        x = min(max(0, x), CGFloat(canvasWidth) - width)
        y = min(max(0, y), CGFloat(canvasHeight) - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
            .intersection(CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
    }

    /// Which edges of the original re-stamp border newly generated terrain.
    /// An edge sitting on the canvas boundary (within rounding) stays hard;
    /// an interior edge feathers into the generated fill.
    static func stampFeatherEdges(priorContentRect rect: CGRect) -> TerrainStampFeatherEdges {
        let epsilon: CGFloat = 0.0005
        return TerrainStampFeatherEdges(
            top: rect.minY > epsilon,
            bottom: rect.maxY < 1 - epsilon,
            left: rect.minX > epsilon,
            right: rect.maxX < 1 - epsilon
        )
    }

    /// The feather width actually usable for a stamp of the given pixel size:
    /// the fixed width, clamped so opposing feathers can never overlap.
    static func stampFeatherWidth(stampSize: CGSize) -> CGFloat {
        let limit = min(stampSize.width, stampSize.height) / 4
        return max(0, min(stampFeatherPixels, limit))
    }
}
