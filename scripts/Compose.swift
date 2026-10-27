import AppKit
import ImageIO
import UniformTypeIdentifiers

// Composes marketing images from the rendered panel previews.
// Usage: Compose <screens-dir> <lang>
let arguments = CommandLine.arguments
guard arguments.count == 3 else { fputs("usage: Compose <screens-dir> <lang>\n", stderr); exit(2) }
let directory = URL(fileURLWithPath: arguments[1]), lang = arguments[2]
func load(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: directory.appendingPathComponent("\(name)-\(lang).png")) else {
        fputs("missing \(name)-\(lang).png\n", stderr); exit(1)
    }
    return image
}
func pixels(_ image: NSImage) -> CGImage { image.cgImage(forProposedRect: nil, context: nil, hints: nil)! }
func canvas(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context); return context.makeImage()!
}
func write(_ image: CGImage, _ name: String) {
    let url = directory.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil); CGImageDestinationFinalize(destination)
}
func background(_ context: CGContext, _ width: Int, _ height: Int) {
    let colors = [CGColor(srgbRed: 0.83, green: 0.88, blue: 0.97, alpha: 1), CGColor(srgbRed: 0.95, green: 0.90, blue: 0.96, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
}
// Panels are rendered at 2x; draw each with rounded corners and a soft shadow like a real popover.
func panel(_ context: CGContext, _ image: CGImage, at origin: CGPoint) {
    let rect = CGRect(origin: origin, size: CGSize(width: image.width, height: image.height))
    let shape = CGPath(roundedRect: rect, cornerWidth: 28, cornerHeight: 28, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 60, color: CGColor(gray: 0, alpha: 0.28))
    context.addPath(shape); context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fillPath()
    context.restoreGState()
    context.saveGState(); context.addPath(shape); context.clip(); context.draw(image, in: rect); context.restoreGState()
}

// Hero: a menu bar strip with the status item and the disk panel dropped below it.
let disk = pixels(load("disk")), network = pixels(load("network")), status = pixels(load("status-item"))
let heroWidth = 2400, heroHeight = 1640, barHeight = 64
let hero = canvas(width: heroWidth, height: heroHeight) { context in
    background(context, heroWidth, heroHeight)
    context.setFillColor(CGColor(gray: 1, alpha: 0.72))
    context.fill(CGRect(x: 0, y: heroHeight - barHeight, width: heroWidth, height: barHeight))
    let itemX = heroWidth - 760
    context.setFillColor(CGColor(gray: 0, alpha: 0.1))
    context.addPath(CGPath(roundedRect: CGRect(x: itemX - 14, y: heroHeight - barHeight + 8, width: status.width + 28, height: barHeight - 16), cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.fillPath()
    context.draw(status, in: CGRect(x: itemX, y: heroHeight - barHeight + (barHeight - status.height) / 2, width: status.width, height: status.height))
    panel(context, disk, at: CGPoint(x: itemX + status.width / 2 - disk.width / 2, y: heroHeight - barHeight - 24 - disk.height))
    panel(context, network, at: CGPoint(x: 260, y: 120))
}
write(hero, "hero-\(lang).png")

// Comparison: the same AI coding tools ranked by network traffic and by disk writes.
let compare = canvas(width: network.width * 2 + 240, height: network.height + 160) { context in
    background(context, network.width * 2 + 240, network.height + 160)
    panel(context, network, at: CGPoint(x: 80, y: 80))
    panel(context, disk, at: CGPoint(x: network.width + 160, y: 80))
}
write(compare, "compare-\(lang).png")

// Demo GIF: a slow tour of the three tabs, the 7-day trend and alerts, at 1x to stay small.
let frames = ["network", "disk", "disk-7d", "health"].map { pixels(load($0)) }
let gifURL = directory.appendingPathComponent("demo-\(lang).gif")
let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for frame in frames {
    let scaled = canvas(width: frame.width / 2, height: frame.height / 2) { context in
        context.interpolationQuality = .high
        context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width / 2, height: frame.height / 2))
    }
    CGImageDestinationAddImage(gif, scaled, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 2.5]] as CFDictionary)
}
CGImageDestinationFinalize(gif)
print("Composed hero, compare and demo for \(lang)")
