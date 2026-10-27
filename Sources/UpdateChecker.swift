import AppKit
import Foundation

@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    private var checking = false
    private var task: Task<Void, Never>?
    private var progressPanel: NSPanel?
    private var progressLabel: NSTextField?
    private var cancelButton: NSButton?
    func check() {
        guard !checking else { return }
        checking = true
        task = Task {
            var workspace: URL?, plan: UpdateInstallPlan?, handedOff = false
            defer {
                progressPanel?.close(); progressPanel = nil; progressLabel = nil; cancelButton = nil
                if !handedOff {
                    if let plan { try? FileManager.default.removeItem(at: plan.staging) }
                    if let workspace { try? FileManager.default.removeItem(at: workspace) }
                }
                checking = false; task = nil
            }
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForResource = 180
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                var request = URLRequest(url: URL(string: "https://api.github.com/repos/tab16360/flowcat/releases/latest")!)
                request.timeoutInterval = 20
                request.setValue("FlowCat-update-check", forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw updateError(tr("GitHub did not return release information. Try again later.", "GitHub 暂时无法返回版本信息，请稍后重试。")) }
                let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
                guard ReleaseInfo.validVersion(release.version), !release.draft, !release.prerelease else { throw updateError(tr("The release information looks invalid. Try again later.", "版本信息异常，请稍后重试。")) }
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                guard release.isNewer(than: current) else {
                    alert.messageText = tr("FlowCat is up to date", "已是最新版本"); alert.informativeText = tr("Current version: ", "当前版本：") + current
                    alert.addButton(withTitle: tr("OK", "好")); alert.runModal(); return
                }
                guard let asset = release.installationAsset else { throw updateError(tr("This release has no verifiable Apple Silicon package yet.", "该版本暂时缺少可校验的 Apple Silicon 安装包。")) }
                alert.messageText = tr("FlowCat \(release.version) is available", "流量喵 \(release.version) 可更新")
                alert.informativeText = tr("Current version: ", "当前版本：") + current + "\n\n\(String((release.body ?? "").prefix(800)))\n\n" + tr("FlowCat downloads and verifies the package, replaces the app and relaunches. History and settings are kept.", "自动下载并校验安装包，替换应用后重新启动。历史和设置保留。")
                alert.addButton(withTitle: tr("Install and Relaunch", "安装并重启")); alert.addButton(withTitle: tr("Later", "稍后"))
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                showProgress(tr("Downloading \(release.version)…", "正在下载 \(release.version)…"))
                let root = UpdateInstaller.cacheRoot
                let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                workspace = directory
                var downloadRequest = URLRequest(url: asset.browser_download_url); downloadRequest.timeoutInterval = 60
                let (temporary, downloadResponse) = try await session.download(for: downloadRequest)
                guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200 else { throw updateError(tr("The download failed. Try again later.", "安装包下载失败，请稍后重试。")) }
                try Task.checkCancellation()
                let archive = directory.appendingPathComponent("update.zip")
                try FileManager.default.moveItem(at: temporary, to: archive)
                progressLabel?.stringValue = tr("Verifying the package…", "正在校验安装包并准备替换…")
                let destination = Bundle.main.bundleURL
                let pid = ProcessInfo.processInfo.processIdentifier
                let preparation = Task.detached(priority: .utility) {
                    try UpdateInstaller.prepare(archive: archive, release: release, destination: destination, workspace: directory, parentPID: pid)
                }
                let prepared = try await withTaskCancellationHandler(operation: { try await preparation.value }, onCancel: { preparation.cancel() })
                plan = prepared
                try Task.checkCancellation()
                cancelButton?.isEnabled = false; progressLabel?.stringValue = tr("Saving history and relaunching…", "正在保存记录并重新启动…")
                try UpdateInstaller.startHelper(prepared)
                handedOff = true
                // applicationWillTerminate saves the ledger before the helper observes this PID exiting.
                NSApp.terminate(nil)
            } catch {
                if !(error is CancellationError) && !Task.isCancelled && (error as? URLError)?.code != .cancelled { showError(error.localizedDescription) }
            }
        }
    }
    private func showProgress(_ text: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = tr("Update FlowCat", "更新流量喵"); panel.isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: text); label.frame = NSRect(x: 24, y: 100, width: 372, height: 38)
        let progress = NSProgressIndicator(frame: NSRect(x: 24, y: 70, width: 372, height: 16))
        progress.style = .bar; progress.isIndeterminate = true; progress.startAnimation(nil)
        let cancel = NSButton(title: tr("Cancel", "取消"), target: self, action: #selector(cancelDownload)); cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: 308, y: 20, width: 88, height: 30)
        panel.contentView?.addSubview(label); panel.contentView?.addSubview(progress); panel.contentView?.addSubview(cancel)
        panel.center(); panel.makeKeyAndOrderFront(nil)
        progressPanel = panel; progressLabel = label; cancelButton = cancel
    }
    @objc private func cancelDownload() { task?.cancel(); cancelButton?.isEnabled = false; progressLabel?.stringValue = tr("Cancelling…", "正在取消…") }
    private func showError(_ message: String) {
        progressPanel?.close()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert(); alert.messageText = tr("Could not finish the update", "无法完成更新"); alert.informativeText = message
        alert.addButton(withTitle: tr("OK", "好")); alert.runModal()
    }
}
