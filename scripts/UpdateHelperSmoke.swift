import Foundation

@main enum UpdateHelperSmoke {
    static func main() throws {
        let manager = FileManager.default
        let source = URL(fileURLWithPath: CommandLine.arguments[1]).resolvingSymlinksInPath()
        let version = try UpdateInstaller.metadata(source)["CFBundleShortVersionString"] as! String
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FlowCat-helper-smoke-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let cacheBase = UpdateInstaller.cacheRoot.appendingPathComponent("smoke-\(UUID().uuidString)")
        try manager.createDirectory(at: cacheBase, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root); try? manager.removeItem(at: cacheBase) }
        let target = root.appendingPathComponent("Installed ' literal.app")
        try manager.copyItem(at: source, to: target)
        let plistURL = target.appendingPathComponent("Contents/Info.plist")
        var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as! [String: Any]
        plist["CFBundleShortVersionString"] = "0.0.0"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
        try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", target.path])
        let zip = root.appendingPathComponent("new.zip")
        try UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", source.path, zip.path])
        let bytes = try Data(contentsOf: zip)
        let name = "FlowCat-\(version)-arm64.zip"
        let asset = ReleaseInfo.Asset(name: name, browser_download_url: URL(string: "https://github.com/tab16360/flowcat/releases/download/v\(version)/\(name)")!, digest: "sha256:" + UpdateArchive.checksum(bytes), size: bytes.count)
        let release = ReleaseInfo(tag_name: "v\(version)", body: nil, draft: false, prerelease: false, assets: [asset])
        let workspace = cacheBase.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: workspace, withIntermediateDirectories: true)
        let parent = Process(); parent.executableURL = URL(fileURLWithPath: "/bin/sleep"); parent.arguments = ["1"]; try parent.run()
        DispatchQueue.global().async { parent.waitUntilExit() }
        let plan = try UpdateInstaller.prepare(archive: zip, release: release, destination: target, workspace: workspace, parentPID: parent.processIdentifier, relaunch: false)
        let helper = try UpdateInstaller.startHelper(plan)
        helper.waitUntilExit()
        guard helper.terminationStatus == 0, try UpdateInstaller.metadata(target)["CFBundleShortVersionString"] as? String == version,
            try UpdateInstaller.metadata(workspace.deletingLastPathComponent().appendingPathComponent("previous.app"))["CFBundleShortVersionString"] as? String == "0.0.0" else { throw updateError("Detached updater smoke check failed") }
        print("PASS: real packaged executable runs detached updater and replaces isolated app without starting GUI or sampler")
    }
}
