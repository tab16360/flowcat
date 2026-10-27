import AppKit

// Approved B design: transparent cat outline with three traffic bars.
enum BrandIcon {
    static func draw(in rect: NSRect, application: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.maxY)
        transform.scaleX(by: rect.width / 64, yBy: -rect.height / 64)
        transform.concat()
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: 16, y: 28))
        outline.line(to: NSPoint(x: 14, y: 10))
        outline.line(to: NSPoint(x: 27, y: 21))
        outline.curve(to: NSPoint(x: 37, y: 21), controlPoint1: NSPoint(x: 30, y: 20), controlPoint2: NSPoint(x: 34, y: 20))
        outline.line(to: NSPoint(x: 50, y: 10))
        outline.line(to: NSPoint(x: 48, y: 28))
        outline.curve(to: NSPoint(x: 51, y: 46), controlPoint1: NSPoint(x: 53, y: 32), controlPoint2: NSPoint(x: 55, y: 40))
        outline.curve(to: NSPoint(x: 32, y: 56), controlPoint1: NSPoint(x: 47, y: 53), controlPoint2: NSPoint(x: 40, y: 56))
        outline.curve(to: NSPoint(x: 13, y: 46), controlPoint1: NSPoint(x: 24, y: 56), controlPoint2: NSPoint(x: 17, y: 53))
        outline.curve(to: NSPoint(x: 16, y: 28), controlPoint1: NSPoint(x: 9, y: 40), controlPoint2: NSPoint(x: 11, y: 32))
        outline.close()
        let bars = NSBezierPath()
        for (x, top) in [(23.0, 38.0), (32.0, 33.0), (41.0, 28.0)] {
            bars.move(to: NSPoint(x: x, y: 44)); bars.line(to: NSPoint(x: x, y: top))
        }
        NSColor(srgbRed: 0.13, green: 0.16, blue: 0.19, alpha: 1).setStroke()
        for path in [outline, bars] {
            path.lineWidth = application ? 1.9 : 2.6
            path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke()
        }
    }
    static func menuBar() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect, application: false); return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "FlowCat"
        return image
    }
}
