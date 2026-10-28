import AppKit
import SwiftUI

// Collects preferences that were previously split across the panel, its menu and the status-item menu.
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    func show(_ monitor: TrafficMonitor) {
        monitor.refreshLoginStatus()
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 540),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = tr("FlowCat Settings", "流量喵设置"); window.isReleasedWhenClosed = false; window.delegate = self
        // Assigning a controller resizes the window to its view; restore the fixed form size afterwards.
        window.contentViewController = NSHostingController(rootView: SettingsView(monitor: monitor, disk: monitor.disk, alerts: monitor.disk.alerts))
        window.setContentSize(NSSize(width: 440, height: 540))
        self.window = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { window = nil }
}
struct SettingsView: View {
    @ObservedObject var monitor: TrafficMonitor
    @ObservedObject var disk: DiskMonitor
    @ObservedObject var alerts: DiskAlertController
    @ObservedObject var l10n = Localization.shared
    @ViewState private var loginError = ""
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    var body: some View {
        Form {
            Section(tr("Menu Bar", "菜单栏显示")) {
                Toggle(tr("Today's total traffic", "今日累计流量"), isOn: $monitor.showMenuBarTotal)
                Toggle(tr("Network speed", "实时网速"), isOn: $monitor.showMenuBarSpeed)
                Toggle(tr("Disk read/write speed", "磁盘读写速度"), isOn: $disk.showMenuBarDiskSpeed)
            }
            Section {
                Toggle(tr("Include LAN in totals", "总量包含局域网"), isOn: $monitor.includeLAN)
            } header: { Text(tr("Network", "网络统计")) } footer: {
                Text(tr("Affects totals and the menu bar total only. When off, recognized LAN traffic is subtracted as an estimate; app rankings and live speed are unchanged.", "只影响总量与菜单栏累计。关闭后扣除已识别的局域网流量，结果为估算；应用排行与实时网速不受影响。"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            // Low-frequency items share one section so the window fits without scrolling.
            Section {
                Picker(tr("Language", "语言"), selection: $l10n.preference) {
                    Text(tr("System default", "跟随系统")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("简体中文").tag(AppLanguage.chinese)
                }
                Toggle(tr("Launch at login", "登录时自动启动"), isOn: Binding(get: { monitor.loginEnabled }, set: { enabled in
                    do { try monitor.setLogin(enabled); loginError = "" }
                    catch { loginError = tr("Move FlowCat to the Applications folder first.", "请先把应用放入“应用程序”，再设置登录启动。") }
                }))
                if !loginError.isEmpty { Text(loginError).font(.system(size: 11)).foregroundStyle(.orange) }
                LabeledContent(tr("Disk write alerts", "磁盘写入提醒")) {
                    HStack(spacing: 10) {
                        Text(alerts.preferences.enabled ? tr("On", "已开启") : tr("Off", "未开启")).foregroundStyle(.secondary)
                        Button(tr("Configure…", "设置…")) { DiskAlertWindow.shared.show(disk) }
                    }
                }
                LabeledContent(tr("Version ", "版本 ") + version) {
                    Button(tr("Check for Updates…", "检查更新…")) { UpdateChecker.shared.check() }
                }
            } header: { Text(tr("General", "通用")) }
        }.formStyle(.grouped).frame(width: 440, height: 540).environment(\.locale, appLocale)
    }
}
