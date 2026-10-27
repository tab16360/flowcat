import Foundation
import AppKit
import CryptoKit
import Security
import Darwin

func updateError(_ text: String) -> NSError {
    NSError(domain: "FlowCat.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
}

enum UpdateArchive {
    static let maximumBytes = 64 * 1024 * 1024
    static func checksum(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func validName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0") else { return false }
        var parts = name.split(separator: "/", omittingEmptySubsequences: false)
        if parts.last == "" { parts.removeLast() }
        return !parts.contains(where: { $0 == ".." || $0 == "." || $0.isEmpty })
            && (name == "流量喵.app/" || name.hasPrefix("流量喵.app/") || name.hasPrefix("__MACOSX/"))
    }
    // ditto ZIPs contain UTF-8 names without the UTF-8 flag; zipinfo corrupts their display.
    // Read both central and local headers before extraction instead of trusting CLI filename output.
    static func validate(_ data: Data) throws {
        guard (22...maximumBytes).contains(data.count) else { throw updateError(tr("The package size is unexpected.", "安装包大小异常。")) }
        let bytes = [UInt8](data)
        func number(_ offset: Int, _ length: Int) throws -> Int {
            guard offset >= 0, offset + length <= bytes.count else { throw updateError(tr("The package is incomplete.", "安装包结构不完整。")) }
            return (0..<length).reduce(0) { $0 | Int(bytes[offset + $1]) << ($1 * 8) }
        }
        var end: Int?
        for offset in stride(from: bytes.count - 22, through: max(0, bytes.count - 65557), by: -1) {
            if try number(offset, 4) == 0x06054b50, try offset + 22 + number(offset + 20, 2) == bytes.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw updateError(tr("This package format is not supported.", "不支持该安装包格式。")) }
        let count = try number(end + 10, 2), start = try number(end + 16, 4), size = try number(end + 12, 4)
        guard (1...2000).contains(count), try number(end + 8, 2) == count, start + size == end else { throw updateError(tr("The package directory is invalid.", "安装包目录异常。")) }
        var cursor = start, inflated = 0, names = Set<String>()
        for _ in 0..<count {
            guard cursor + 46 <= end, try number(cursor, 4) == 0x02014b50 else { throw updateError(tr("The package directory is damaged.", "安装包目录损坏。")) }
            let flags = try number(cursor + 8, 2), compressed = try number(cursor + 20, 4)
            let nameLength = try number(cursor + 28, 2), extraLength = try number(cursor + 30, 2), commentLength = try number(cursor + 32, 2)
            let next = cursor + 46 + nameLength + extraLength + commentLength
            guard next <= end, flags & 1 == 0, try number(cursor + 34, 2) == 0 else { throw updateError(tr("A package entry is invalid.", "安装包条目异常。")) }
            let rawName = Data(bytes[(cursor + 46)..<(cursor + 46 + nameLength)])
            guard let name = String(data: rawName, encoding: .utf8), validName(name), names.insert(name).inserted else { throw updateError(tr("The package contains unsafe or duplicate paths.", "安装包包含不安全或重复的路径。")) }
            guard try (number(cursor + 38, 4) >> 16) & 0xf000 != 0xa000 else { throw updateError(tr("The package must not contain symbolic links.", "安装包不应包含符号链接。")) }
            inflated += try number(cursor + 24, 4)
            guard inflated <= maximumBytes else { throw updateError(tr("The unpacked size is unexpected.", "安装包解压后体积异常。")) }
            let local = try number(cursor + 42, 4)
            guard local + 30 <= start, try number(local, 4) == 0x04034b50 else { throw updateError(tr("A package file header is invalid.", "安装包文件头异常。")) }
            let localNameLength = try number(local + 26, 2), localExtraLength = try number(local + 28, 2)
            let payload = local + 30 + localNameLength + localExtraLength
            guard payload + compressed <= start, try number(local + 6, 2) == flags,
                try number(local + 8, 2) == number(cursor + 10, 2),
                Data(bytes[(local + 30)..<(local + 30 + localNameLength)]) == rawName else { throw updateError(tr("A package file header does not match its directory entry.", "安装包文件头与目录不一致。")) }
            cursor = next
        }
        guard cursor == end, names.contains("流量喵.app/Contents/Info.plist"), names.contains("流量喵.app/Contents/MacOS/FlowCat") else { throw updateError(tr("The package is missing the app.", "安装包缺少应用文件。")) }
    }
}

struct UpdateLaunchReceipt: Codable { let version: String; let path: String; let pid: Int32 }

struct UpdateInstallPlan: Codable {
    let destination: URL
    let staging: URL
    let workspace: URL
    let oldVersion: String
    let newVersion: String
    let parentPID: Int32
    let relaunch: Bool
    var incoming: URL { staging.appendingPathComponent("incoming.app") }
    var backup: URL { staging.appendingPathComponent("previous.app") }
}

enum UpdateInstaller {
    static let identifier = "local.gww.trafficledger"
    static var cacheRoot: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("local.gww.trafficledger/Updates")
    }
    static func validWorkspace(_ workspace: URL) -> Bool {
        workspace.isFileURL && UUID(uuidString: workspace.lastPathComponent) != nil
            && workspace.resolvingSymlinksInPath().path.hasPrefix(cacheRoot.resolvingSymlinksInPath().path + "/")
    }
    static func metadata(_ app: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            plist["CFBundleIdentifier"] as? String == identifier, plist["CFBundleExecutable"] as? String == "FlowCat",
            plist["CFBundlePackageType"] as? String == "APPL" else { throw updateError(tr("The app identity check failed.", "应用身份校验失败。")) }
        return plist
    }
    static func signingTeam(_ app: URL) throws -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { throw updateError(tr("Could not read the app signature.", "无法读取应用签名。")) }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess else { throw updateError(tr("Could not read signing information.", "无法读取签名信息。")) }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }
    static func validTeamTransition(from old: String?, to new: String?) -> Bool { old == nil || old == new }
    @discardableResult static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let timeout = DispatchWorkItem { [weak process] in if let process, process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); timeout.cancel()
        guard process.terminationStatus == 0 else { throw updateError(tr("Update step failed: ", "更新步骤失败：") + String(String(decoding: data, as: UTF8.self).prefix(500))) }
        return String(decoding: data, as: UTF8.self)
    }
    static func validateApp(_ app: URL, version: String) throws {
        guard app.pathExtension == "app", app.standardizedFileURL.path == app.resolvingSymlinksInPath().path,
            try metadata(app)["CFBundleShortVersionString"] as? String == version else { throw updateError(tr("The package version or path check failed.", "安装包版本或路径校验失败。")) }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }
    // Stage on the destination volume, so the signed bundle is renamed, never overwritten in place.
    static func prepare(archive: URL, release: ReleaseInfo, destination: URL, workspace: URL, parentPID: Int32, relaunch: Bool = true) throws -> UpdateInstallPlan {
        guard archive.isFileURL, destination.isFileURL, validWorkspace(workspace) else { throw updateError(tr("The update folder is outside the app cache.", "更新工作目录不在应用缓存范围内。")) }
        guard let asset = release.installationAsset, let expected = asset.sha256 else { throw updateError(tr("This release has no reliable checksum.", "该版本缺少可靠的安装包校验信息。")) }
        let old = try metadata(destination)
        guard let oldVersion = old["CFBundleShortVersionString"] as? String, release.isNewer(than: oldVersion) else { throw updateError(tr("The new version must be newer than the current one.", "安装版本必须高于当前版本。")) }
        guard destination.pathExtension == "app", destination.standardizedFileURL.path == destination.resolvingSymlinksInPath().path,
            FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path),
            !destination.path.contains("/AppTranslocation/") else { throw updateError(tr("The current location cannot be replaced. Move the app to a writable Applications folder and try again.", "当前安装位置无法替换。请先将应用移到可写的“应用程序”目录后重试。")) }
        let size = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size == asset.size else { throw updateError(tr("The downloaded size does not match.", "下载的安装包大小不匹配。")) }
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard UpdateArchive.checksum(data) == expected else { throw updateError(tr("SHA-256 verification failed; the current version was not changed.", "安装包 SHA-256 校验失败，旧版未改动。")) }
        try Task.checkCancellation(); try UpdateArchive.validate(data)
        let extracted = workspace.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: false)
        try run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
        let candidate = extracted.appendingPathComponent("流量喵.app")
        try validateApp(candidate, version: release.version)
        guard validTeamTransition(from: try signingTeam(destination), to: try signingTeam(candidate)) else { throw updateError(tr("The new version is signed by a different team.", "新版签名团队与当前应用不一致。")) }
        try Task.checkCancellation()
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".FlowCat-update-\(UUID().uuidString)", isDirectory: true)
        let plan = UpdateInstallPlan(destination: destination, staging: staging, workspace: workspace,
            oldVersion: oldVersion, newVersion: release.version, parentPID: parentPID, relaunch: relaunch)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            try FileManager.default.copyItem(at: candidate, to: plan.incoming)
            try validateApp(plan.incoming, version: release.version)
            try Task.checkCancellation()
            return plan
        } catch { try? FileManager.default.removeItem(at: staging); throw error }
    }
    static func launch(_ app: URL) throws { try run("/usr/bin/open", ["-n", app.path]) }
    static func launchUpdated(_ app: URL, receipt: URL) throws {
        try run("/usr/bin/open", ["-n", app.path, "--args", "--update-receipt", receipt.path])
    }
    static func acknowledgeLaunch() {
        guard let i = CommandLine.arguments.firstIndex(of: "--update-receipt"), CommandLine.arguments.count > i + 1 else { return }
        let receipt = URL(fileURLWithPath: CommandLine.arguments[i + 1]).standardizedFileURL
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("local.gww.trafficledger/Updates")
        guard receipt.lastPathComponent == "launch.json", receipt.deletingLastPathComponent().deletingLastPathComponent().path == root.path,
            UUID(uuidString: receipt.deletingLastPathComponent().lastPathComponent) != nil,
            receipt.path == receipt.resolvingSymlinksInPath().path else { return }
        let info = UpdateLaunchReceipt(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            path: Bundle.main.bundleURL.path, pid: ProcessInfo.processInfo.processIdentifier)
        if let data = try? JSONEncoder().encode(info) { try? data.write(to: receipt, options: .atomic) }
    }
    @discardableResult static func startHelper(_ plan: UpdateInstallPlan) throws -> Process {
        let helper = plan.workspace.appendingPathComponent("update-helper")
        try FileManager.default.copyItem(at: plan.incoming.appendingPathComponent("Contents/MacOS/FlowCat"), to: helper)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let file = plan.workspace.appendingPathComponent("plan.json")
        try JSONEncoder().encode(plan).write(to: file, options: .atomic)
        let log = plan.workspace.appendingPathComponent("update.log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let output = try FileHandle(forWritingTo: log)
        let process = Process(); process.executableURL = helper; process.arguments = ["--finish-update", file.path]
        process.standardOutput = output; process.standardError = output; process.standardInput = FileHandle.nullDevice
        try process.run(); try? output.close(); return process
    }
    static func finish(_ plan: UpdateInstallPlan, launchApp: (URL, URL) throws -> Void = launchUpdated) throws {
        let manager = FileManager.default
        guard plan.destination.isFileURL, plan.staging.isFileURL, validWorkspace(plan.workspace),
            plan.staging.standardizedFileURL.path == plan.staging.resolvingSymlinksInPath().path,
            plan.parentPID > 1, plan.parentPID != ProcessInfo.processInfo.processIdentifier,
            plan.destination.deletingLastPathComponent().path == plan.staging.deletingLastPathComponent().path,
            plan.staging.lastPathComponent.hasPrefix(".FlowCat-update-"),
            UUID(uuidString: String(plan.staging.lastPathComponent.dropFirst(".FlowCat-update-".count))) != nil else { throw updateError(tr("The update plan is invalid.", "更新计划无效。")) }
        let deadline = Date().addingTimeInterval(30)
        while kill(plan.parentPID, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        guard kill(plan.parentPID, 0) != 0 else { throw updateError(tr("The old app did not quit, so the update stopped.", "旧程序未退出，更新已停止。")) }
        try validateApp(plan.destination, version: plan.oldVersion)
        try validateApp(plan.incoming, version: plan.newVersion)
        guard validTeamTransition(from: try signingTeam(plan.destination), to: try signingTeam(plan.incoming)),
            !manager.fileExists(atPath: plan.backup.path) else { throw updateError(tr("The update state changed. Check for updates again.", "更新状态已改变，请重新检查更新。")) }
        var movedOld = false, installedNew = false
        do {
            try manager.moveItem(at: plan.destination, to: plan.backup); movedOld = true
            try manager.moveItem(at: plan.incoming, to: plan.destination); installedNew = true
            if plan.relaunch {
                let receipt = plan.workspace.appendingPathComponent("launch.json")
                try launchApp(plan.destination, receipt)
                let readyDeadline = Date().addingTimeInterval(20)
                var ready = false
                while Date() < readyDeadline {
                    if let data = try? Data(contentsOf: receipt), let info = try? JSONDecoder().decode(UpdateLaunchReceipt.self, from: data),
                        info.version == plan.newVersion, info.path == plan.destination.path, kill(info.pid, 0) == 0 { ready = true; break }
                    Thread.sleep(forTimeInterval: 0.2)
                }
                guard ready else { throw updateError(tr("The new version did not start; restoring the previous one.", "新版未能正常启动，正在恢复旧版。")) }
            }
        } catch {
            do {
                if plan.relaunch && installedNew {
                    let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                        .filter { $0.bundleURL?.standardizedFileURL.path == plan.destination.standardizedFileURL.path }
                    for app in running { _ = app.terminate() }
                    let stopDeadline = Date().addingTimeInterval(5)
                    while running.contains(where: { !$0.isTerminated }) && Date() < stopDeadline { Thread.sleep(forTimeInterval: 0.1) }
                    guard running.allSatisfy({ $0.isTerminated }) else { throw updateError(tr("The new version is still running; the previous one was kept in the backup folder.", "新版仍在运行，旧版保留在备份目录中。")) }
                }
                if installedNew { try manager.moveItem(at: plan.destination, to: plan.staging.appendingPathComponent("failed.app")) }
                if movedOld { try manager.moveItem(at: plan.backup, to: plan.destination) }
            } catch { throw updateError(tr("Could not restore the previous version. It was kept at: ", "恢复旧版失败。旧版保留在：") + "\(plan.backup.path)\n\(error.localizedDescription)") }
            throw error
        }
        // Keep one previous version for recovery; cache housekeeping must not undo a successful install.
        let previous = plan.workspace.deletingLastPathComponent().appendingPathComponent("previous.app")
        do {
            if manager.fileExists(atPath: previous.path) { _ = try metadata(previous); try manager.removeItem(at: previous) }
            try manager.moveItem(at: plan.backup, to: previous)
            try? manager.removeItem(at: plan.staging)
            try? manager.removeItem(at: plan.workspace)
        } catch { /* The original remains in the staging directory if cache cleanup fails. */ }
    }
}
