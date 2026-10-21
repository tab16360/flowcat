import AppKit

enum ProcessLocation {
    static func existingURL(_ path: String) -> URL? {
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
    static func reveal(_ path: String) {
        guard let url = existingURL(path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
