import AppKit
import SwiftUI

final class DiskAlertWindow: NSObject, NSWindowDelegate {
    static let shared = DiskAlertWindow()
    private var window: NSWindow?
    func show(_ disk: DiskMonitor) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = tr("Disk Write Alerts", "磁盘写入提醒"); window.minSize = NSSize(width: 510, height: 500)
        window.isReleasedWhenClosed = false; window.delegate = self
        window.contentViewController = NSHostingController(rootView: DiskAlertView(disk: disk, alerts: disk.alerts))
        self.window = window; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        disk.alerts.refreshPermission()
    }
    func windowWillClose(_ notification: Notification) { window = nil }
}
struct DiskAlertView: View {
    @ObservedObject var disk: DiskMonitor
    @ObservedObject var alerts: DiskAlertController
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var l10n = Localization.shared
    @ViewState private var appFilter = ""
    private var palette: Palette { Palette(dark: scheme == .dark) }
    // Apps with today's writes come first; the rest follow alphabetically.
    private var apps: [(String, String)] {
        var result: [String: String] = [:]
        for day in disk.ledger.days.values { for (path, app) in day.processes { result[path] = app.name } }
        for alert in alerts.memory.recent { result[alert.path] = alert.name }
        for path in alerts.preferences.overrides.keys { result[path] = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
        for path in alerts.preferences.ignored { if result[path] == nil { result[path] = URL(fileURLWithPath: path).lastPathComponent } }
        let today = disk.ledger.days[DateKeys.day(Date())]?.processes ?? [:]
        return result.map { ($0.key, $0.value) }
            .filter { appFilter.isEmpty || $0.1.localizedCaseInsensitiveContains(appFilter) || $0.0.localizedCaseInsensitiveContains(appFilter) || $0.0 == alerts.selectedPath }
            .sorted {
                let a = today[$0.0]?.bytes.written ?? 0, b = today[$1.0]?.bytes.written ?? 0
                return a == b ? $0.1.localizedStandardCompare($1.1) == .orderedAscending : a > b
            }
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(tr("Disk Write Alerts", "磁盘写入提醒"), isOn: $alerts.preferences.enabled).font(.system(size: 18, weight: .semibold)).toggleStyle(.switch)
                        Text(tr("Spot sustained writes and budget overruns for every app FlowCat can sample. It never judges whether a task is normal and never quits a process.", "发现持续写入和预算超额。适用于所有可采样应用，不判断任务是否正常，也不会自动结束进程。"))
                            .font(.system(size: 12)).foregroundStyle(palette.secondary)
                        HStack {
                            Text(alerts.notificationStatus).font(.system(size: 11)).foregroundStyle(palette.secondary)
                            Spacer()
                            switch alerts.notificationAuthorization {
                            case .notDetermined: Button(tr("Allow Notifications", "允许系统通知")) { alerts.requestPermission() }.controlSize(.small)
                            case .denied:
                                Button(tr("Open System Settings", "打开系统设置")) {
                                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") { NSWorkspace.shared.open(url) }
                                }.controlSize(.small)
                            default: EmptyView()
                            }
                        }
                    }
                    section(tr("Default rules", "默认规则"), info: tr("Choose “Off” to disable a single rule.\n\nSustained high writes: at least 9.5 of the last 10 full minutes were sampled, and at least 8 of them were above the rate threshold.\n\nThe hourly budget only counts writes sampled in the last hour; the daily budget uses today's history.", "选择“关闭”可停用单项规则。\n\n持续高写入：最近 10 个完整分钟至少采到 9.5 分钟，其中至少 8 分钟达到速率阈值。\n\n小时预算只统计最近一小时采到的写入；每日预算沿用今日历史。")) {
                        policyFields($alerts.preferences.policy)
                    }.disabled(!alerts.preferences.enabled)
                    section(tr("Per-app settings", "单应用设置与详情")) {
                        HStack(spacing: 8) {
                            Picker(tr("App", "应用"), selection: $alerts.selectedPath) {
                                Text(tr("Choose an app…", "选择应用…")).tag(nil as String?)
                                ForEach(apps, id: \.0) { path, name in Text(name).tag(Optional(path)) }
                            }
                            TextField(tr("Filter", "筛选"), text: $appFilter).textFieldStyle(.roundedBorder).frame(width: 120)
                                .help(tr("Filter apps by name or path", "按名称或路径筛选应用列表"))
                        }
                        if let path = alerts.selectedPath {
                            Text(path).font(.system(size: 10)).foregroundStyle(palette.secondary).textSelection(.enabled)
                            HStack {
                                Text(tr("Alerts", "提醒")).font(.system(size: 12))
                                Spacer()
                                Picker(tr("Alerts", "提醒"), selection: Binding(get: { alerts.state(for: path) }, set: { alerts.setState($0, for: path) })) {
                                    Text(tr("On", "正常")).tag(DiskAlertController.AppState.active)
                                    Text(alerts.state(for: path) == .snoozed ? tr("Paused until ", "暂停至 ") + (alerts.preferences.snoozedUntil[path].map { appDate($0, date: .omitted, time: .shortened) } ?? "") : tr("Pause 1 hour", "暂停 1 小时"))
                                        .tag(DiskAlertController.AppState.snoozed)
                                    Text(tr("Mute", "不再提醒")).tag(DiskAlertController.AppState.ignored)
                                }.pickerStyle(.segmented).labelsHidden().fixedSize()
                            }
                            Toggle(tr("Use custom thresholds", "使用独立阈值"), isOn: Binding(get: { alerts.preferences.overrides[path] != nil }, set: {
                                if $0 { alerts.preferences.overrides[path] = alerts.preferences.policy }
                                else { alerts.preferences.overrides.removeValue(forKey: path) }
                            })).font(.system(size: 12))
                            if alerts.preferences.overrides[path] != nil {
                                policyFields(Binding(get: { alerts.preferences.overrides[path] ?? alerts.preferences.policy }, set: { alerts.preferences.overrides[path] = $0 }))
                            }
                            writeChart(path)
                        } else {
                            Text(tr("Choose an app to see recent writes or override the defaults. Apps with the most writes today are listed first.", "选择应用查看近期写入，或覆盖默认阈值。今日写入较多的应用排在前面。"))
                                .font(.system(size: 11)).foregroundStyle(palette.secondary)
                        }
                    }.disabled(!alerts.preferences.enabled).id("app")
                    section(tr("Recent alerts", "最近提醒")) {
                        if alerts.memory.recent.isEmpty {
                            Text(tr("No alerts yet", "还没有提醒")).font(.system(size: 13, weight: .medium))
                            Text(alerts.preferences.enabled ? tr("Alerts appear here when a rule is met, even without notification permission.", "达到规则后显示在这里；未授权系统通知也会保留。") : tr("Turn alerts on to start checking; the daily budget includes today's history.", "开启后开始采样判断；每日预算会计入今日已有历史。"))
                                .font(.system(size: 11)).foregroundStyle(palette.secondary)
                        }
                        ForEach(Array(alerts.memory.recent.enumerated()), id: \.element.id) { index, alert in
                            if index > 0 { Divider() }
                            Button {
                                alerts.selectedPath = alert.path
                                withAnimation { proxy.scrollTo("app", anchor: .top) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(alert.name + " · " + alert.kind.title).fontWeight(.medium); Spacer(); Text(appDate(alert.date, date: .abbreviated, time: .shortened)).foregroundStyle(palette.secondary) }
                                    Text(alerts.summary(alert)).foregroundStyle(palette.secondary)
                                }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(tr("Show this app's write curve and settings", "查看此应用的写入曲线与设置"))
                        }
                        if !alerts.deliveryError.isEmpty { Text(alerts.deliveryError).font(.system(size: 11)).foregroundStyle(palette.warning) }
                        if !alerts.persistenceError.isEmpty { Text(alerts.persistenceError).font(.system(size: 11)).foregroundStyle(palette.warning) }
                    }
                    InfoButton(title: tr("Storage and alert frequency", "保存与提醒频率"), text: tr("Settings and the latest 40 alerts are stored on this Mac only. Minute curves stay in memory and are cleared when FlowCat quits. Sampling gaps are not filled in.\n\nEach app gets at most one alert per type per hour; sustained and hourly rules re-arm after 5 minutes below the threshold, and the daily budget alerts once a day.\n\nPausing, muting and notification settings never change disk statistics.", "仅在本机保存设置与最近 40 条提醒；分钟曲线不落盘，关闭应用后清空。采样中断不补算。\n\n每应用每类提醒至少间隔 1 小时，持续／小时规则恢复 5 分钟后才可再次提醒；每日预算每天一次。\n\n暂停、不再提醒和通知设置都不影响原有磁盘统计。"))
                        .font(.system(size: 11))
                }.padding(24)
            }
        }.foregroundStyle(palette.text).background(palette.background).environment(\.locale, appLocale)
    }
    private func section<Content: View>(_ title: String, info: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let info { InfoButton(text: info, help: tr("About the rules", "规则说明")) }
            }
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func policyFields(_ policy: Binding<DiskAlertPolicy>) -> some View {
        VStack(spacing: 10) {
            rule(tr("Sustained write rate", "持续写入阈值"), value: policy.sustainedMBps, choices: [0, 0.25, 0.5, 1, 2, 5, 10], unit: "MB/s")
            rule(tr("Hourly budget per app", "单应用小时预算"), value: policy.hourlyGB, choices: [0, 0.5, 1, 2, 5, 10, 20, 50], unit: "GB")
            rule(tr("Daily budget per app", "单应用每日预算"), value: policy.dailyGB, choices: [0, 2, 5, 10, 20, 50, 100, 500], unit: "GB")
        }
    }
    private func rule(_ title: String, value: Binding<Double>, choices: [Double], unit: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12)); Spacer()
            Picker(title, selection: value) {
                ForEach(choices, id: \.self) { number in Text(number == 0 ? tr("Off", "关闭") : "\(number.formatted()) \(unit)").tag(number) }
            }.labelsHidden().frame(width: 130)
        }
    }
    private func writeChart(_ path: String) -> some View {
        let minutes = alerts.engine.minutes(for: path, now: Date())
        let current = Int(Date().timeIntervalSince1970 / 60)
        let byMinute = Dictionary(uniqueKeysWithValues: minutes.map { ($0.minute, $0) })
        let top = max(1, minutes.map(\.bytes).max() ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text(tr("Last hour · writes per minute", "最近一小时 · 每分钟写入")); Spacer(); Text(diskVolume(minutes.reduce(0) { DiskBytes.plus($0, $1.bytes) })) }.font(.system(size: 11, weight: .medium))
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach((current-59)...current, id: \.self) { minute in
                        Rectangle().fill(byMinute[minute] == nil ? palette.track : palette.accent)
                            .frame(height: byMinute[minute] == nil ? 2 : max(2, geometry.size.height * Double(byMinute[minute]!.bytes) / Double(top)))
                            .help(byMinute[minute].map { "\(diskVolume($0.bytes)) · " + tr("\(Int($0.seconds)) s sampled", "覆盖 \(Int($0.seconds)) 秒") } ?? tr("No samples", "未采到记录"))
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom)
            }.frame(height: 64)
            HStack { Text(tr("1 hour ago", "一小时前")); Spacer(); Text(tr("Now", "现在")) }.font(.system(size: 10)).foregroundStyle(palette.secondary)
            if minutes.isEmpty { Text(tr("The curve builds up once alerts are on; missing samples do not mean zero writes.", "开启提醒后开始积累曲线；未采到记录不表示写入为零。")).font(.system(size: 11)).foregroundStyle(palette.secondary) }
        }.padding(.top, 6)
    }
}
