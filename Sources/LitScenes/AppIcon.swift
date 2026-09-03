import AppKit

/// The public, non-confusing Community mark. Official commercial packages do
/// not call this renderer; their rights-holder-provided icon comes from the app
/// bundle configured by the official release pipeline.
enum LitScenesAppIcon {
    static func image(size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        return image
    }

    static func draw(in rect: NSRect) {
        let scale = min(rect.width, rect.height)
        let bounds = NSRect(
            x: rect.midX - scale / 2,
            y: rect.midY - scale / 2,
            width: scale,
            height: scale
        )

        let background = NSBezierPath(
            roundedRect: bounds,
            xRadius: scale * 0.22,
            yRadius: scale * 0.22
        )
        NSGradient(colors: [
            NSColor(calibratedRed: 0.055, green: 0.078, blue: 0.082, alpha: 1),
            NSColor(calibratedRed: 0.095, green: 0.145, blue: 0.132, alpha: 1),
        ])?.draw(in: background, angle: 315)

        let frameColor = NSColor(calibratedRed: 0.93, green: 0.88, blue: 0.72, alpha: 0.96)
        for (index, inset) in [0.19, 0.28, 0.37].enumerated() {
            let offset = CGFloat(index - 1) * scale * 0.035
            let frame = NSBezierPath(
                roundedRect: bounds.insetBy(dx: scale * inset, dy: scale * inset)
                    .offsetBy(dx: offset, dy: -offset),
                xRadius: scale * 0.045,
                yRadius: scale * 0.045
            )
            frame.lineWidth = scale * 0.024
            frameColor.withAlphaComponent(0.45 + CGFloat(index) * 0.22).setStroke()
            frame.stroke()
        }

        let storyLine = NSBezierPath()
        storyLine.move(to: NSPoint(x: bounds.minX + scale * 0.29, y: bounds.minY + scale * 0.28))
        storyLine.curve(
            to: NSPoint(x: bounds.minX + scale * 0.72, y: bounds.minY + scale * 0.70),
            controlPoint1: NSPoint(x: bounds.minX + scale * 0.40, y: bounds.minY + scale * 0.68),
            controlPoint2: NSPoint(x: bounds.minX + scale * 0.60, y: bounds.minY + scale * 0.33)
        )
        storyLine.lineWidth = scale * 0.022
        storyLine.lineCapStyle = .round
        NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.32, alpha: 0.95).setStroke()
        storyLine.stroke()

        if LitScenesReleaseIdentity.current.channel == .development {
            drawDevelopmentBadge(in: bounds, scale: scale)
        }
    }

    private static func drawDevelopmentBadge(in bounds: NSRect, scale: CGFloat) {
        let badge = NSRect(
            x: bounds.minX + scale * 0.25,
            y: bounds.minY + scale * 0.08,
            width: scale * 0.50,
            height: scale * 0.14
        )
        NSColor(calibratedRed: 0.93, green: 0.48, blue: 0.20, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: badge, xRadius: scale * 0.06, yRadius: scale * 0.06).fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSString(string: "DEVELOPMENT").draw(in: badge.offsetBy(dx: 0, dy: scale * 0.018), withAttributes: [
            .font: NSFont.systemFont(ofSize: scale * 0.046, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1),
            .paragraphStyle: paragraph,
        ])
    }
}
