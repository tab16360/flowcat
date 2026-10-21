import AppKit

// Each enabled metric group gets one column; two rows share a compact width.
// A single template image keeps tint and highlighting consistent with the menu bar.
enum MenuBarSpeeds {
    static func columns(total: String?, network: String?, read: String?, write: String?) -> [[String]] {
        var columns: [[String]] = []
        let traffic = [total, network].compactMap { $0 }
        if !traffic.isEmpty { columns.append(traffic) }
        if let read, let write { columns.append(["读 " + read, "写 " + write]) }
        return columns
    }
    static func image(total: String? = nil, network: String?, read: String? = nil, write: String? = nil) -> NSImage {
        let columns = columns(total: total, network: network, read: read, write: write)
        let small: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium), .foregroundColor: NSColor.black]
        let normal: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.black]
        let widths = columns.map { rows -> CGFloat in
            let attributes = rows.count == 2 ? small : normal
            return ceil(rows.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0)
        }
        let image = NSImage(size: NSSize(width: 18 + widths.reduce(0, +) + CGFloat(columns.count * 6), height: 22))
        image.lockFocus()
        BrandIcon.menuBar().draw(in: NSRect(x: 0, y: 2, width: 18, height: 18))
        var x: CGFloat = 24
        for (index, rows) in columns.enumerated() {
            let attributes = rows.count == 2 ? small : normal
            for (row, label) in rows.enumerated() {
                let y: CGFloat = rows.count == 2 ? (row == 0 ? 11 : 0) : floor((22 - (label as NSString).size(withAttributes: attributes).height) / 2)
                (label as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            }
            x += widths[index] + 6
        }
        image.unlockFocus(); image.isTemplate = true
        return image
    }
    static func preview() -> NSImage {
        let examples: [(String, String?, String?, String?, String?)] = [
            ("仅累计", "今 1.28 GB", nil, nil, nil),
            ("仅网速", nil, "↓219.00 KB/s", nil, nil),
            ("累计 + 网速", "今 1.28 GB", "↓219.00 KB/s", nil, nil),
            ("累计 + 网速 + 磁盘", "今 1.28 GB", "↓219.00 KB/s", "1.28 MB/s", "640.00 KB/s"),
            ("仅磁盘", nil, nil, "1.28 MB/s", "640.00 KB/s")]
        let image = NSImage(size: NSSize(width: 460, height: 210))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 460, height: 210).fill()
        for (index, example) in examples.enumerated() {
            let y = CGFloat(175 - index * 40)
            (example.0 as NSString).draw(at: NSPoint(x: 10, y: y+4), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray])
            self.image(total: example.1, network: example.2, read: example.3, write: example.4).draw(at: NSPoint(x: 155, y: y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        image.unlockFocus(); return image
    }
}
