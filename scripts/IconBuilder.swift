import AppKit

@main enum IconBuilder {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
            let pixels = points * scale
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate icon bitmap") }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            BrandIcon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), application: true)
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try png.write(to: directory.appendingPathComponent(name))
        }
    }
}
