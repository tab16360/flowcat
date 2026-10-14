import Foundation

@main enum UpdateIntegration {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FlowCat-update-tests-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let cacheBase = UpdateInstaller.cacheRoot.appendingPathComponent("tests-\(UUID().uuidString)")
        try manager.createDirectory(at: cacheBase, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root); try? manager.removeItem(at: cacheBase) }
        func expect(_ condition: Bool, _ label: String) {
            guard condition else { fatalError("FAIL: \(label)") }; print("PASS: \(label)")
        }
        func fixture(_ folder: String, _ version: String, id: String = UpdateInstaller.identifier) throws -> URL {
            let app = root.appendingPathComponent(folder).appendingPathComponent("流量喵.app")
            let executable = app.appendingPathComponent("Contents/MacOS/FlowCat")
            try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[0]), to: executable)
            let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "FlowCat", "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
            try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
            return app
        }
        func archive(_ app: URL, name: String) throws -> (URL, ReleaseInfo) {
            let zip = root.appendingPathComponent(name + ".zip")
            try UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", app.path, zip.path])
            let data = try Data(contentsOf: zip)
            let asset = ReleaseInfo.Asset(name: "FlowCat-1.4.0-arm64.zip", browser_download_url: URL(string: "https://github.com/tab16360/flowcat/releases/download/v1.4.0/FlowCat-1.4.0-arm64.zip")!, digest: "sha256:" + UpdateArchive.checksum(data), size: data.count)
            return (zip, ReleaseInfo(tag_name: "v1.4.0", body: nil, draft: false, prerelease: false, assets: [asset]))
        }
        func destination(_ name: String, old: URL) throws -> URL {
            let target = root.appendingPathComponent(name).appendingPathComponent("流量喵 ' space $literal.app")
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.copyItem(at: old, to: target); return target
        }
        func workspace() throws -> URL {
            let url = cacheBase.appendingPathComponent(UUID().uuidString)
            try manager.createDirectory(at: url, withIntermediateDirectories: true); return url
        }
        let old = try fixture("old", "1.3.11"), new = try fixture("new", "1.4.0")
        let (zip, release) = try archive(new, name: "valid")
        try UpdateArchive.validate(Data(contentsOf: zip))
        expect(release.installationAsset != nil, "valid Unicode ditto ZIP and GitHub digest accepted")
        let ledger = root.appendingPathComponent("ledger.json"); let history = Data("original history".utf8); try history.write(to: ledger)
        let target = try destination("successful install", old: old)
        let parent = Process(); parent.executableURL = URL(fileURLWithPath: "/bin/sleep"); parent.arguments = ["1"]; try parent.run()
        DispatchQueue.global().async { parent.waitUntilExit() }
        let plan = try UpdateInstaller.prepare(archive: zip, release: release, destination: target, workspace: workspace(), parentPID: parent.processIdentifier, relaunch: false)
        expect(try UpdateInstaller.metadata(target)["CFBundleShortVersionString"] as? String == "1.3.11", "preparation leaves running app untouched")
        try UpdateInstaller.finish(plan)
        expect(!parent.isRunning, "replacement waits for parent exit")
        expect(try UpdateInstaller.metadata(target)["CFBundleShortVersionString"] as? String == "1.4.0", "signed app bundle replaced using literal Unicode and quoted paths")
        expect(try UpdateInstaller.metadata(plan.workspace.deletingLastPathComponent().appendingPathComponent("previous.app"))["CFBundleShortVersionString"] as? String == "1.3.11", "one previous version kept for recovery")
        expect(try Data(contentsOf: ledger) == history, "application update never changes external traffic history")
        let rollbackTarget = try destination("rollback", old: old)
        let rollbackPlan = try UpdateInstaller.prepare(archive: zip, release: release, destination: rollbackTarget, workspace: workspace(), parentPID: Int32.max, relaunch: true)
        do { try UpdateInstaller.finish(rollbackPlan, launchApp: { _, _ in throw updateError("simulated launch failure") }); fatalError("launch failure should throw") }
        catch { expect(try UpdateInstaller.metadata(rollbackTarget)["CFBundleShortVersionString"] as? String == "1.3.11", "launch failure restores previous app") }
        expect(manager.fileExists(atPath: rollbackPlan.staging.appendingPathComponent("failed.app").path), "failed candidate retained without overwriting old app")
        let healthyTarget = try destination("readiness", old: old)
        let healthyPlan = try UpdateInstaller.prepare(archive: zip, release: release, destination: healthyTarget, workspace: workspace(), parentPID: Int32.max, relaunch: true)
        try UpdateInstaller.finish(healthyPlan, launchApp: { app, receipt in
            let info = UpdateLaunchReceipt(version: "1.4.0", path: app.path, pid: ProcessInfo.processInfo.processIdentifier)
            try JSONEncoder().encode(info).write(to: receipt)
        })
        expect(try UpdateInstaller.metadata(healthyTarget)["CFBundleShortVersionString"] as? String == "1.4.0", "successful launch receipt commits installation")
        let badTarget = try destination("rejected package", old: old)
        let badAsset = ReleaseInfo.Asset(name: release.assets[0].name, browser_download_url: release.assets[0].browser_download_url, digest: "sha256:" + String(repeating: "0", count: 64), size: release.assets[0].size)
        let badRelease = ReleaseInfo(tag_name: release.tag_name, body: nil, draft: false, prerelease: false, assets: [badAsset])
        do { _ = try UpdateInstaller.prepare(archive: zip, release: badRelease, destination: badTarget, workspace: workspace(), parentPID: Int32.max); fatalError("checksum mismatch should throw") }
        catch { expect(try UpdateInstaller.metadata(badTarget)["CFBundleShortVersionString"] as? String == "1.3.11", "digest mismatch refuses install and preserves current app") }
        let tampered = try fixture("tampered", "1.4.0")
        let binary = tampered.appendingPathComponent("Contents/MacOS/FlowCat")
        var binaryData = try Data(contentsOf: binary); binaryData[4096] ^= 1; try binaryData.write(to: binary)
        let (tamperedZip, tamperedRelease) = try archive(tampered, name: "tampered")
        do { _ = try UpdateInstaller.prepare(archive: tamperedZip, release: tamperedRelease, destination: badTarget, workspace: workspace(), parentPID: Int32.max); fatalError("invalid signature should throw") }
        catch { expect(try UpdateInstaller.metadata(badTarget)["CFBundleShortVersionString"] as? String == "1.3.11", "invalid code signature refuses install even when download checksum matches") }
        let other = try fixture("foreign", "1.4.0", id: "foreign.app")
        let (otherZip, otherRelease) = try archive(other, name: "foreign")
        do { _ = try UpdateInstaller.prepare(archive: otherZip, release: otherRelease, destination: badTarget, workspace: workspace(), parentPID: Int32.max); fatalError("wrong identity should throw") }
        catch { expect(try UpdateInstaller.metadata(badTarget)["CFBundleShortVersionString"] as? String == "1.3.11", "different bundle identity cannot replace FlowCat") }
        let (oldZip, oldRelease) = try archive(old, name: "wrong-version")
        do { _ = try UpdateInstaller.prepare(archive: oldZip, release: oldRelease, destination: badTarget, workspace: workspace(), parentPID: Int32.max); fatalError("wrong version should throw") }
        catch { expect(try UpdateInstaller.metadata(badTarget)["CFBundleShortVersionString"] as? String == "1.3.11", "package version must match the selected release") }
        var linked = try Data(contentsOf: zip)
        let central = linked.range(of: Data([0x50,0x4b,0x01,0x02]))!.lowerBound
        linked[central + 38] = 0; linked[central + 39] = 0; linked[central + 40] = 0xff; linked[central + 41] = 0xa1
        do { try UpdateArchive.validate(linked); fatalError("symlink ZIP should throw") } catch { print("PASS: ZIP symlink entries rejected before extraction") }
        print("All 14 updater integration checks passed.")
    }
}
