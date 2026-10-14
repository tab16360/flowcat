import AppKit

// Reuse the site's cat outline for both the application icon and menu bar template.
enum BrandIcon {
    static func draw(in rect: NSRect, application: Bool) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / 64, yBy: rect.height / 64)
        transform.concat()
        if application {
            let tile = NSBezierPath(roundedRect: NSRect(x: 5, y: 5, width: 54, height: 54), xRadius: 12, yRadius: 12)
            NSColor(srgbRed: 0.98, green: 0.976, blue: 0.96, alpha: 1).setFill(); tile.fill()
            NSColor(srgbRed: 0.84, green: 0.85, blue: 0.81, alpha: 1).setStroke()
            tile.lineWidth = 0.4; tile.stroke()
            let inset = NSAffineTransform(); inset.translateX(by: 8, yBy: 8); inset.scale(by: 0.75); inset.concat()
        }
        let flip = NSAffineTransform(); flip.translateX(by: 0, yBy: 64); flip.scaleX(by: 1, yBy: -1); flip.concat()
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: 15, y: 29))
        for point in [NSPoint(x: 13, y: 9), NSPoint(x: 28, y: 21), NSPoint(x: 37, y: 21), NSPoint(x: 51, y: 9), NSPoint(x: 49, y: 30)] { outline.line(to: point) }
        outline.curve(to: NSPoint(x: 32, y: 57), controlPoint1: NSPoint(x: 57, y: 48), controlPoint2: NSPoint(x: 48, y: 57))
        outline.curve(to: NSPoint(x: 15, y: 29), controlPoint1: NSPoint(x: 16, y: 57), controlPoint2: NSPoint(x: 8, y: 47))
        outline.close()
        let face = NSBezierPath()
        func line(_ points: [NSPoint]) {
            face.move(to: points[0]); for point in points.dropFirst() { face.line(to: point) }
        }
        line([NSPoint(x: 22, y: 34), NSPoint(x: 22, y: 37)])
        line([NSPoint(x: 42, y: 34), NSPoint(x: 42, y: 37)])
        line([NSPoint(x: 28, y: 45), NSPoint(x: 32, y: 48), NSPoint(x: 36, y: 45)])
        line([NSPoint(x: 32, y: 48), NSPoint(x: 32, y: 53)])
        for pair in [[NSPoint(x: 7, y: 40), NSPoint(x: 19, y: 43)], [NSPoint(x: 6, y: 48), NSPoint(x: 20, y: 47)], [NSPoint(x: 45, y: 43), NSPoint(x: 57, y: 40)], [NSPoint(x: 44, y: 47), NSPoint(x: 58, y: 48)]] { line(pair) }
        NSColor(srgbRed: 0.14, green: 0.16, blue: 0.14, alpha: 1).setStroke()
        for path in [outline, face] { path.lineWidth = application ? 3 : 3.2; path.lineCapStyle = .round; path.lineJoinStyle = .round; path.stroke() }
    }
    static func menuBar() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            draw(in: rect, application: false); return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "流量喵"
        return image
    }
}
