import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSPopoverDelegate {
    var item: NSStatusItem!
    let monitor = TrafficMonitor()
    let popover = NSPopover()
    var hosting: NSHostingController<LedgerView>?
    var started = false
    private var outsideMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var menuObservers: [NSObjectProtocol] = []
    private var menuDepth = 0
    private var menuTracking: Bool { menuDepth > 0 }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Avoid two samplers double-counting the same computer after repeated clicks.
        let identifier = Bundle.main.bundleIdentifier ?? "local.gww.trafficledger"
        let siblings = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        if siblings.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = BrandIcon.menuBar()
            button.imagePosition = .imageLeading
            button.title = ""
            button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            button.target = self; button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.delegate = self
        monitor.onUpdate = { [weak self] in
            guard let self else { return }
            self.refreshStatusItem()
        }
        monitor.disk.onUpdate = { [weak self] in self?.refreshStatusItem() }
        monitor.disk.alerts.onOpen = { [weak self] in
            guard let self else { return }
            self.popover.performClose(nil); DiskAlertWindow.shared.show(self.monitor.disk)
        }
        monitor.disk.alerts.configureNotifications()
        refreshStatusItem()
        started = true; monitor.start()
        UpdateInstaller.acknowledgeLaunch()
    }
    private func refreshStatusItem() {
        guard let button = item.button else { return }
        let network = "↓\(volume(UInt64(max(0, monitor.download))))/s"
        let reading = "\(diskVolume(UInt64(max(0, monitor.disk.readRate))))/s"
        let writing = "\(diskVolume(UInt64(max(0, monitor.disk.writeRate))))/s"
        let today = monitor.menuBarTotal.map { volume($0.total) } ?? "—"
        let totalLabel = monitor.showMenuBarTotal ? (monitor.includeLAN ? "今 " : "今≈ ") + today : nil
        let speedLabel = monitor.showMenuBarSpeed ? (monitor.paused ? "暂停" : network) : nil
        let diskVisible = monitor.disk.showMenuBarDiskSpeed && !monitor.paused
        button.title = ""; button.imagePosition = .imageOnly; button.imageScaling = .scaleNone
        button.image = MenuBarSpeeds.image(total: totalLabel,
            network: speedLabel ?? (monitor.paused && monitor.disk.showMenuBarDiskSpeed && totalLabel == nil ? "暂停" : nil),
            read: diskVisible ? reading : nil, write: diskVisible ? writing : nil)
        button.toolTip = "流量喵\(monitor.paused ? " · 已暂停" : "") · 今日\(monitor.includeLAN ? "总流量" : "扣除局域网估算") \(today)"
        if monitor.disk.showMenuBarDiskSpeed {
            button.toolTip = (button.toolTip ?? "流量喵") + "\n磁盘读取 \(reading)，写入 \(writing)"
        }
        button.setAccessibilityLabel("流量喵，\(monitor.paused ? "已暂停，" : "")\(monitor.showMenuBarTotal ? "今日累计 " + today + "，" : "")打开统计面板")

    }
    @objc func toggle() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu()
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else { openStatistics() }
    }
    @objc private func openStatistics() {
        monitor.refreshLoginStatus()
        if popover.isShown { return }
        if let button = item.button {
            configurePanel()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            startOutsideDismissal()
        }
    }
    private func showContextMenu() {
        guard let button = item.button else { return }
        popover.performClose(nil)
        monitor.refreshLoginStatus()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        func add(_ title: String, action: Selector) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
            return entry
        }
        _ = add("打开统计面板", action: #selector(openStatistics))
        _ = add(monitor.paused ? "继续记录" : "暂停记录", action: #selector(toggleRecording))
        menu.addItem(.separator())
        let login = add("登录时自动启动", action: #selector(toggleLogin))
        login.state = monitor.loginEnabled ? .on : .off
        let total = add("菜单栏显示累计流量", action: #selector(toggleMenuBarTotal))
        total.state = monitor.showMenuBarTotal ? .on : .off
        let speed = add("菜单栏显示网速", action: #selector(toggleMenuBarSpeed))
        speed.state = monitor.showMenuBarSpeed ? .on : .off
        let diskSpeed = add("菜单栏显示磁盘读写", action: #selector(toggleMenuBarDiskSpeed))
        diskSpeed.state = monitor.disk.showMenuBarDiskSpeed ? .on : .off
        _ = add("导出 CSV…", action: #selector(exportCSV))
        _ = add("磁盘写入提醒…", action: #selector(openDiskAlerts))
        _ = add("检查更新…", action: #selector(checkUpdates))
        menu.addItem(.separator())
        _ = add("退出流量喵", action: #selector(quit))
        // Let the status item anchor its menu below the menu bar. A generic
        // popUp at the button origin can clip rows against the screen edge.
        item.menu = menu
        button.performClick(nil)
    }
    func menuDidClose(_ menu: NSMenu) {
        // Restore the button action so the next left click opens statistics.
        if item.menu === menu { item.menu = nil }
    }
    func popoverDidClose(_ notification: Notification) {
        stopOutsideDismissal()
        // Release the view graph and decoded icons while only the sampler runs.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.popover.isShown else { return }
            self.popover.contentViewController = nil
            self.hosting = nil
            self.monitor.clearIcons()
        }
    }
    private func startOutsideDismissal() {
        stopOutsideDismissal()
        // Native picker menus can leave transient popovers open after tracking.
        // Keep menu item selection intact, then explicitly close on the next outside click.
        let center = NotificationCenter.default
        menuObservers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in self?.menuDepth += 1 })
        menuObservers.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in if let self { self.menuDepth = max(0, self.menuDepth - 1) } })
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            guard let self, self.popover.isShown, !self.menuTracking else { return }
            self.popover.performClose(nil)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            guard let self, self.popover.isShown, !self.menuTracking else { return event }
            if event.window?.level == .popUpMenu { return event }
            let point = NSEvent.mouseLocation
            if let window = self.popover.contentViewController?.view.window, window.frame.contains(point) { return event }
            if let button = self.item.button, let window = button.window,
                window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point) { return event }
            self.popover.performClose(nil)
            return event
        }
    }
    private func stopOutsideDismissal() {
        if let outsideMouseMonitor { NSEvent.removeMonitor(outsideMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        outsideMouseMonitor = nil; localMouseMonitor = nil
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        menuObservers.removeAll(); menuDepth = 0
    }
    @MainActor @objc private func checkUpdates() { UpdateChecker.shared.check() }
    @objc private func openDiskAlerts() { popover.performClose(nil); DiskAlertWindow.shared.show(monitor.disk) }
    @objc private func toggleMenuBarDiskSpeed() { monitor.disk.showMenuBarDiskSpeed.toggle() }
    @objc private func toggleMenuBarTotal() { monitor.showMenuBarTotal.toggle() }
    @objc private func toggleMenuBarSpeed() { monitor.showMenuBarSpeed.toggle() }
    @objc private func toggleRecording() { monitor.togglePause() }
    @objc private func exportCSV() {
        NSApp.activate(ignoringOtherApps: true)
        if monitor.diskTab { monitor.disk.export() } else { monitor.export() }
    }
    @objc private func toggleLogin() {
        do { try monitor.setLogin(!monitor.loginEnabled) }
        catch {
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "无法设置登录启动"
            alert.informativeText = "请先把应用放入“应用程序”，再重试。\n\(error.localizedDescription)"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
    @objc private func quit() { monitor.save(); NSApp.terminate(nil) }
    private func configurePanel() {
        let screen = item.button?.window?.screen ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 800)
        let dimension = PanelLayout.size(screenWidth: frame.width, availableHeight: frame.height)
        let size = CGSize(width: dimension.width, height: dimension.height)
        if let hosting {
            hosting.rootView = LedgerView(monitor: monitor, panelSize: size)
            hosting.preferredContentSize = size
        } else {
            let controller = NSHostingController(rootView: LedgerView(monitor: monitor, panelSize: size))
            controller.sizingOptions = []
            controller.preferredContentSize = size
            hosting = controller; popover.contentViewController = controller
        }
        popover.contentSize = size
    }
    func applicationWillTerminate(_ notification: Notification) { stopOutsideDismissal(); if started { monitor.save() } }
}
// Detached updater mode runs before app initialization or the traffic sampler.
if let index = CommandLine.arguments.firstIndex(of: "--finish-update") {
    guard CommandLine.arguments.count > index + 1 else { fputs("Missing update plan\n", stderr); exit(2) }
    var plan: UpdateInstallPlan?
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        let decoded = try JSONDecoder().decode(UpdateInstallPlan.self, from: data); plan = decoded
        try UpdateInstaller.finish(decoded); exit(0)
    } catch {
        fputs("Update failed: \(error.localizedDescription)\n", stderr)
        if let plan, plan.relaunch {
            try? UpdateInstaller.launch(plan.destination)
            let helperApp = NSApplication.shared; helperApp.setActivationPolicy(.accessory); helperApp.activate(ignoringOtherApps: true)
            let alert = NSAlert(); alert.messageText = "更新未完成"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好"); alert.runModal()
        }
        exit(1)
    }
}
if CommandLine.arguments.contains("--disk-diagnostics") {
    let start = Date(), first = DiskSampler.capture()
    let samplingMS = Date().timeIntervalSince(start)*1000
    Thread.sleep(forTimeInterval: 1)
    var accumulator = DiskAccumulator(), history = DiskLedger()
    _ = accumulator.apply(first, ledger: &history)
    let delta = accumulator.apply(DiskSampler.capture(), ledger: &history) ?? DiskBytes()
    let hardware = try DiskHardware.read()
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print("Processes: \(first.counters.count), denied: \(first.denied), sample: \(String(format: "%.2f", samplingMS)) ms")
    print("Observed one-second delta: read \(delta.read), written \(delta.written)")
    for device in hardware {
        var native = FCNVMeHealth()
        let status = device.id.withCString { fc_read_nvme($0, &native) }
        print("Native NVMe \(device.id): status=\(status), error=\(String(native.error, radix: 16)), temperature=\(native.temperature), used=\(native.used)")
    }
    print(String(decoding: try encoder.encode(hardware), as: UTF8.self))
    exit(0)
}
let app = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--render-menu-preview"), CommandLine.arguments.count > index + 1 {
    let image = MenuBarSpeeds.preview()
    if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
       let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) {
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
    }
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let preview = TrafficMonitor(file: destination.deletingLastPathComponent().appendingPathComponent("preview-ledger-unused.json"))
    let originalLANPreference = UserDefaults.standard.object(forKey: "includeLAN")
    preview.includeLAN = !CommandLine.arguments.contains("--exclude-lan")
    var previewBreakdown = TrafficBreakdown()
    previewBreakdown.local = Bytes(received: 1_800_000_000, sent: 90_000_000)
    preview.ledger = Ledger(firstStarted: Date())
    preview.ledger.add(day: DateKeys.day(Date()), physical: Bytes(received: 2630000000, sent: 180000000),
        processes: ["UU远程": Bytes(received: 2400000000, sent: 21000000),
                    "Claude Code": Bytes(received: 56000000, sent: 27000000),
                    "ssh": Bytes(received: 24000000, sent: 6000000),
                    "verge-mihomo": Bytes(received: 78000000, sent: 80000000),
                    "Tailscale": Bytes(received: 33000000, sent: 8500000),
                    "ChatGPT": Bytes(received: 35000000, sent: 16000000)], seconds: 14400, breakdown: previewBreakdown)
    if CommandLine.arguments.contains("--no-lan-data") { preview.ledger.days[DateKeys.day(Date())]?.withoutLAN = nil }
    if let networkIndex = CommandLine.arguments.firstIndex(of: "--current-network"), networkIndex + 1 < CommandLine.arguments.count {
        let name = CommandLine.arguments[networkIndex + 1]
        preview.currentNetwork = NetworkContext(key: "wifi:" + name, name: name, identified: true)
    }
    preview.disk.isPreview = true
    if CommandLine.arguments.contains("--disk") {
        preview.diskTab = true
        preview.disk.healthView = CommandLine.arguments.contains("--health")
        let now = Date(), day = DateKeys.day(now)
        let uses: [String: DiskProcessUsage] = [
            "/Applications/Google Chrome.app": DiskProcessUsage(name: "Google Chrome", path: "/Applications/Google Chrome.app", bytes: DiskBytes(read: 4_110_000_000, written: 12_840_000_000)),
            "kernel_task": DiskProcessUsage(name: "kernel_task", path: "kernel_task", bytes: DiskBytes(read: 2_340_000_000, written: 6_120_000_000)),
            "/Applications/Cursor.app": DiskProcessUsage(name: "Cursor", path: "/Applications/Cursor.app", bytes: DiskBytes(read: 1_620_000_000, written: 2_970_000_000)),
            "mds_stores": DiskProcessUsage(name: "mds_stores", path: "/System/Library/mds_stores", bytes: DiskBytes(read: 2_740_000_000, written: 1_660_000_000))]
        var record = DiskDay(processes: uses, seconds: 30360)
        let start = Calendar.current.startOfDay(for: now)
        for hour in 0..<24 {
            let date = Calendar.current.date(byAdding: .hour, value: hour, to: start)!
            if date <= now { record.hours[String(Int(date.timeIntervalSince1970))] = DiskBucket(bytes: DiskBytes(written: UInt64((hour*19+13)%65)*1_000_000), seconds: 600) }
        }
        preview.disk.ledger.days[day] = record
        preview.disk.readRate = 1_280_000; preview.disk.writeRate = 640_000
        preview.disk.sampledProcesses = 628; preview.disk.denied = 12
        preview.disk.lastSample = now
        preview.disk.devices = [DiskDevice(id: "disk0", name: "APPLE SSD AP0512Q", model: "APPLE SSD AP0512Q", internalDisk: true, capacity: 512_000_000_000, solidState: true, status: .normal, message: "磁盘自身报告未检测到硬件警告。", temperature: 38, enduranceUsed: 3, availableSpare: 100, hostRead: 12_760_000_000_000, hostWritten: 8_420_000_000_000, powerOnHours: 1286, mediaErrors: 0)]
        preview.disk.selectedDevice = "disk0"
        if CommandLine.arguments.contains("--empty") { preview.disk.ledger.days = [:] }
    }
    preview.download = 219000; preview.upload = 2400
    preview.status = "界面预览 · 示例数据"
    if CommandLine.arguments.contains("--dark") { app.appearance = NSAppearance(named: .darkAqua) }
    let alertPreview = CommandLine.arguments.contains("--alerts")
    let size = alertPreview ? CGSize(width: CommandLine.arguments.contains("--narrow") ? 510 : 620, height: 900) : CGSize(width: CommandLine.arguments.contains("--narrow") ? 342 : 460, height: CommandLine.arguments.contains("--short") ? 452 : 640)
    var alertModel = preview.disk.alerts
    if alertPreview {
        let suite = "flowcat-alert-preview-" + UUID().uuidString
        let previewDefaults = UserDefaults(suiteName: suite)!
        let alertFile = destination.deletingLastPathComponent().appendingPathComponent("preview-alerts-unused.json")
        let path = "/Applications/Google Chrome.app"
        if CommandLine.arguments.contains("--alert-detail") {
            let example = DiskWriteAlert(date: Date(), path: path, name: "Google Chrome", kind: .hourly, bytes: 2_120_000_000, seconds: 2700)
            try JSONEncoder().encode(DiskAlertMemory(recent: [example])).write(to: alertFile)
        } else { try? FileManager.default.removeItem(at: alertFile) }
        alertModel = DiskAlertController(file: alertFile, defaults: previewDefaults)
        alertModel.preferences.enabled = true
        if CommandLine.arguments.contains("--alert-detail") {
            alertModel.selectedPath = path
            let now = Date()
            for i in 0..<180 {
                let bytes = UInt64((i * 19 + 7) % 80) * 100_000
                alertModel.ingest(from: now.addingTimeInterval(Double(i - 180) * 10), to: now.addingTimeInterval(Double(i - 179) * 10),
                    processes: [path: DiskProcessUsage(name: "Google Chrome", path: path, bytes: DiskBytes(written: bytes))], daily: [:])
            }
        }
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }
    let view = NSHostingView(rootView: alertPreview ? AnyView(DiskAlertView(disk: preview.disk, alerts: alertModel)) : AnyView(LedgerView(monitor: preview, panelSize: size)))
    view.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: destination) }
    }
    if let originalLANPreference { UserDefaults.standard.set(originalLANPreference, forKey: "includeLAN") }
    else { UserDefaults.standard.removeObject(forKey: "includeLAN") }
    exit(0)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
