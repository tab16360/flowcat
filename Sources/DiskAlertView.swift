import AppKit
import SwiftUI

final class DiskAlertWindow: NSObject, NSWindowDelegate {
    static let shared = DiskAlertWindow()
    private var window: NSWindow?
    func show(_ disk: DiskMonitor) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "磁盘写入提醒"; window.minSize = NSSize(width: 510, height: 500)
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
    private var palette: Palette { Palette(dark: scheme == .dark) }
    private var apps: [(String, String)] {
        var result: [String: String] = [:]
        for day in disk.ledger.days.values { for (path, app) in day.processes { result[path] = app.name } }
        for alert in alerts.memory.recent { result[alert.path] = alert.name }
        for path in alerts.preferences.overrides.keys { result[path] = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
        for path in alerts.preferences.ignored { if result[path] == nil { result[path] = URL(fileURLWithPath: path).lastPathComponent } }
        return result.map { ($0.key, $0.value) }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("磁盘写入提醒", isOn: $alerts.preferences.enabled).font(.system(size: 18, weight: .semibold)).toggleStyle(.switch)
                    Text("发现持续写入和预算超额。适用于所有可采样应用，不判断任务是否正常，也不会自动结束进程。")
                        .font(.system(size: 12)).foregroundStyle(palette.secondary)
                    HStack {
                        Text(alerts.notificationStatus).font(.system(size: 11)).foregroundStyle(palette.secondary)
                        Spacer()
                        Button("允许系统通知") { alerts.requestPermission() }.controlSize(.small)
                    }
                }
                section("默认规则") {
                    policyFields($alerts.preferences.policy)
                    Text("选择“关闭”可停用单项规则。持续高写入：最近 10 个完整分钟至少采到 9.5 分钟，其中至少 8 分钟达到速率阈值。小时预算只统计最近一小时采到的写入；每日预算沿用今日历史。")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary)
                }.disabled(!alerts.preferences.enabled)
                section("单应用设置与详情") {
                    Picker("应用", selection: $alerts.selectedPath) {
                        Text("选择应用…").tag(nil as String?)
                        ForEach(apps, id: \.0) { path, name in Text(name).tag(Optional(path)) }
                    }
                    if let path = alerts.selectedPath {
                        Text(path).font(.system(size: 10)).foregroundStyle(palette.secondary).textSelection(.enabled)
                        Toggle("使用独立阈值", isOn: Binding(get: { alerts.preferences.overrides[path] != nil }, set: {
                            if $0 { alerts.preferences.overrides[path] = alerts.preferences.policy }
                            else { alerts.preferences.overrides.removeValue(forKey: path) }
                        }))
                        if alerts.preferences.overrides[path] != nil {
                            policyFields(Binding(get: { alerts.preferences.overrides[path] ?? alerts.preferences.policy }, set: { alerts.preferences.overrides[path] = $0 }))
                        }
                        HStack {
                            Toggle("不再提醒此应用", isOn: Binding(get: { alerts.preferences.ignored.contains(path) }, set: {
                                if $0 { alerts.preferences.ignored.insert(path) } else { alerts.preferences.ignored.remove(path) }
                            }))
                            Spacer()
                            if let until = alerts.preferences.snoozedUntil[path], until > Date() {
                                Button("恢复提醒") { alerts.preferences.snoozedUntil.removeValue(forKey: path) }
                                Text("至 " + until.formatted(date: .omitted, time: .shortened)).foregroundStyle(palette.secondary)
                            } else { Button("忽略 1 小时") { alerts.snooze(path) } }
                        }.font(.system(size: 11))
                        writeChart(path)
                    } else {
                        Text("选择应用查看近期写入，或覆盖默认阈值。路径用于区分同名应用。")
                            .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    }
                }
                section("最近提醒") {
                    if alerts.memory.recent.isEmpty {
                        Text("还没有提醒").font(.system(size: 13, weight: .medium))
                        Text(alerts.preferences.enabled ? "达到规则后显示在这里；未授权系统通知也会保留。" : "开启后开始采样判断；每日预算会计入今日已有历史。")
                            .font(.system(size: 11)).foregroundStyle(palette.secondary)
                    }
                    ForEach(alerts.memory.recent) { alert in
                        Button { alerts.selectedPath = alert.path } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack { Text(alert.name + " · " + alert.kind.title).fontWeight(.medium); Spacer(); Text(alert.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(palette.secondary) }
                                Text(alerts.summary(alert)).foregroundStyle(palette.secondary)
                            }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                    if !alerts.deliveryError.isEmpty { Text(alerts.deliveryError).font(.system(size: 11)).foregroundStyle(palette.warning) }
                    if !alerts.persistenceError.isEmpty { Text(alerts.persistenceError).font(.system(size: 11)).foregroundStyle(palette.warning) }
                }
                Text("仅在本机保存设置与最近 40 条提醒；分钟曲线不落盘，关闭应用后清空。采样中断不补算。每应用每类提醒至少间隔 1 小时，持续／小时规则恢复 5 分钟后才可再次提醒；每日预算每天一次。忽略项、通知设置不影响原有磁盘统计。")
                    .font(.system(size: 11)).foregroundStyle(palette.secondary)
            }.padding(24)
        }.foregroundStyle(palette.text).background(palette.background)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold))
            content()
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func policyFields(_ policy: Binding<DiskAlertPolicy>) -> some View {
        VStack(spacing: 10) {
            rule("持续写入阈值", value: policy.sustainedMBps, choices: [0, 0.25, 0.5, 1, 2, 5, 10], unit: "MB/s")
            rule("单应用小时预算", value: policy.hourlyGB, choices: [0, 0.5, 1, 2, 5, 10, 20, 50], unit: "GB")
            rule("单应用每日预算", value: policy.dailyGB, choices: [0, 2, 5, 10, 20, 50, 100, 500], unit: "GB")
        }
    }
    private func rule(_ title: String, value: Binding<Double>, choices: [Double], unit: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12)); Spacer()
            Picker(title, selection: value) {
                ForEach(choices, id: \.self) { number in Text(number == 0 ? "关闭" : "\(number.formatted()) \(unit)").tag(number) }
            }.labelsHidden().frame(width: 130)
        }
    }
    private func writeChart(_ path: String) -> some View {
        let minutes = alerts.engine.minutes(for: path, now: Date())
        let current = Int(Date().timeIntervalSince1970 / 60)
        let byMinute = Dictionary(uniqueKeysWithValues: minutes.map { ($0.minute, $0) })
        let top = max(1, minutes.map(\.bytes).max() ?? 0)
        return VStack(alignment: .leading, spacing: 8) {
            HStack { Text("最近一小时 · 每分钟写入"); Spacer(); Text(diskVolume(minutes.reduce(0) { DiskBytes.plus($0, $1.bytes) })) }.font(.system(size: 11, weight: .medium))
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach((current-59)...current, id: \.self) { minute in
                        Rectangle().fill(byMinute[minute] == nil ? palette.track : palette.accent)
                            .frame(height: byMinute[minute] == nil ? 2 : max(2, geometry.size.height * Double(byMinute[minute]!.bytes) / Double(top)))
                            .help(byMinute[minute].map { "\(diskVolume($0.bytes)) · 覆盖 \(Int($0.seconds)) 秒" } ?? "未采到记录")
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom)
            }.frame(height: 64)
            HStack { Text("一小时前"); Spacer(); Text("现在") }.font(.system(size: 10)).foregroundStyle(palette.secondary)
            if minutes.isEmpty { Text("开启提醒后开始积累曲线；未采到记录不表示写入为零。").font(.system(size: 11)).foregroundStyle(palette.secondary) }
        }.padding(.top, 6)
    }
}
