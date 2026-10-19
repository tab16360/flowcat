import AppKit

// Render one template image so AppKit tints the icon and both text rows together,
// including highlighted and dark menu bars. The status button keeps its existing actions.
enum MenuBarSpeeds {
    static func image(network: String?, read: String, write: String) -> NSImage {
        let diskFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let diskAttributes: [NSAttributedString.Key: Any] = [.font: diskFont, .foregroundColor: NSColor.black]
        let networkAttributes: [NSAttributedString.Key: Any] = [.font: networkFont, .foregroundColor: NSColor.black]
        let reading = "读 " + read, writing = "写 " + write
        let readSize = (reading as NSString).size(withAttributes: diskAttributes)
        let writeSize = (writing as NSString).size(withAttributes: diskAttributes)
        let diskWidth = ceil(max(readSize.width, writeSize.width))
        let networkSize = network.map { ($0 as NSString).size(withAttributes: networkAttributes) } ?? .zero
        let networkWidth = network == nil ? 0 : ceil(networkSize.width) + 7
        let height: CGFloat = 22
        let image = NSImage(size: NSSize(width: 18 + 6 + networkWidth + diskWidth, height: height))
        image.lockFocus()
        BrandIcon.menuBar().draw(in: NSRect(x: 0, y: 2, width: 18, height: 18))
        if let network {
            (network as NSString).draw(at: NSPoint(x: 24, y: floor((height-networkSize.height)/2)), withAttributes: networkAttributes)
        }
        // Use two fixed half-height lanes; reserve the wider row for a stable shared column.
        let x = 24 + networkWidth
        (reading as NSString).draw(at: NSPoint(x: x, y: 11), withAttributes: diskAttributes)
        (writing as NSString).draw(at: NSPoint(x: x, y: 0), withAttributes: diskAttributes)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }
    static func preview() -> NSImage {
        let image = NSImage(size: NSSize(width: 340, height: 100))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 340, height: 100).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray]
        for (label, network, y) in [("仅磁盘", nil as String?, CGFloat(60)), ("网速 + 磁盘", "↓219.00 KB/s", CGFloat(20))] {
            (label as NSString).draw(at: NSPoint(x: 10, y: y+4), withAttributes: attributes)
            let speeds = self.image(network: network, read: "1.28 MB/s", write: "640.00 KB/s")
            speeds.draw(at: NSPoint(x: 105, y: y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus()
        return image
    }
}
