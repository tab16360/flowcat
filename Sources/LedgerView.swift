import AppKit
import SwiftUI
import ServiceManagement

// Disambiguate the property wrapper from the newer SDK macro with the same name.
typealias ViewState<Value> = SwiftUI.State<Value>

struct Palette {
    let dark: Bool
    var background: Color { color(0xF5F7FA, 0x191D24) }
    var surface: Color { color(0xFFFFFF, 0x252B34) }
    var text: Color { color(0x1C2633, 0xF1F4F8) }
    var secondary: Color { color(0x526174, 0xB4BECC) }
    var border: Color { color(0xD6DDE7, 0x414B59) }
    var track: Color { color(0xE2E8F1, 0x394351) }
    var accent: Color { color(0x245CC4, 0x9DBEFF) }
    var success: Color { color(0x186744, 0x9BD9B7) }
    var successSurface: Color { color(0xE9F4EE, 0x243B31) }
    var warning: Color { color(0x895013, 0xF2C68C) }
    var warningSurface: Color { color(0xFFF2DF, 0x3D3023) }
    private func color(_ light: UInt32, _ darkValue: UInt32) -> Color {
        let rgb = dark ? darkValue : light
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

struct LedgerView: View {
    @ObservedObject var monitor: TrafficMonitor
    var panelSize = CGSize(width: 460, height: 640)
    var close: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var l10n = Localization.shared
    @ViewState private var search = ""
    @ViewState private var searchVisible = false
    @ViewState private var order = 0
    @ViewState private var showRelays = false
    @ViewState private var loginError = ""
    private var palette: Palette { Palette(dark: scheme == .dark) }
    private var compact: Bool { panelSize.height < 540 }
    private var record: DayRecord { monitor.selected }
    private var total: Bytes? { monitor.includeLAN ? record.physical : record.withoutLAN?.bytes }
    private var totalSeconds: Double { monitor.includeLAN ? record.monitoredSeconds : record.withoutLAN?.seconds ?? 0 }
    private var periodName: String { [0: tr("Today", "今日"), 1: tr("Yesterday", "昨日"), 2: tr("This month", "本月"), 3: tr("Last 7 days", "近 7 天")][monitor.period] ?? tr("Today", "今日") }
    private var networkName: String { monitor.selectedNetwork == "__all__" ? tr("All networks", "全部网络") : monitor.selectedNetwork }
    private var networkFilter: String? { monitor.selectedNetwork == "__all__" ? nil : monitor.selectedNetwork }
    private func metric(_ b: Bytes) -> UInt64 { order == 1 ? b.received : order == 2 ? b.sent : b.total }
    private var rows: [(String, Bytes)] {
        ProcessTraffic.rows(record.processes, relay: showRelays).filter { search.isEmpty || $0.0.localizedCaseInsensitiveContains(search) }.sorted {
            metric($0.1) == metric($1.1) ? $0.0 < $1.0 : metric($0.1) > metric($1.1)
        }
    }
    private var hasError: Bool { monitor.statusIsError }
    private var tab: Int { !monitor.diskTab ? 0 : monitor.disk.healthView ? 2 : 1 }

    var body: some View {
        content
            .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
            .foregroundStyle(palette.text)
            .background(palette.background)
            .background(shortcuts)
            .environment(\.locale, appLocale)
    }
    private var content: some View {
        VStack(spacing: compact ? 8 : 12) {
            header
            tabs
            if monitor.paused { PausedBanner { monitor.togglePause() } }
            if monitor.diskTab {
                DiskView(disk: monitor.disk, monitor: monitor, panelSize: panelSize)
            } else {
                VStack(spacing: compact ? 8 : 10) {
                    filters
                    summary
                    if hasError { errorBanner }
                    processSection
                    footer
                }.frame(minHeight: 0, maxHeight: .infinity)
            }
        }.padding(compact ? 12 : 16)
    }
    // Hidden buttons give the popover keyboard shortcuts without extra chrome.
    private var shortcuts: some View {
        ZStack {
            Button("") { select(0) }.keyboardShortcut("1")
            Button("") { select(1) }.keyboardShortcut("2")
            Button("") { select(2) }.keyboardShortcut("3")
            Button("") { monitor.searchFocusRequest += 1 }.keyboardShortcut("f")
            Button("") { SettingsWindow.shared.show(monitor); close() }.keyboardShortcut(",")
            Button("") { close() }.keyboardShortcut(.cancelAction)
        }.opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }
    private func select(_ index: Int) {
        monitor.diskTab = index > 0
        if index > 0 { monitor.disk.healthView = index == 2 }
    }
    private var tabs: some View {
        HStack(spacing: panelSize.width < 380 ? 12 : 18) {
            navigationTab(tr("Network", "网络"), symbol: "arrow.up.arrow.down", index: 0)
            navigationTab(tr("Disk Activity", "磁盘读写"), symbol: "internaldrive", index: 1)
            navigationTab(tr("Disk Health", "磁盘健康"), symbol: "stethoscope", index: 2)
            Spacer(minLength: 0)
        }.overlay(alignment: .bottom) { Rectangle().fill(palette.border).frame(height: 0.5) }
    }
    private func navigationTab(_ title: String, symbol: String, index: Int) -> some View {
        Button { select(index) } label: {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tab == index ? palette.accent : palette.secondary)
                .padding(.horizontal, 2).padding(.bottom, 9).padding(.top, 3)
                .overlay(alignment: .bottom) {
                    if tab == index { Rectangle().fill(palette.accent).frame(height: 2) }
                }.contentShape(Rectangle())
        }.buttonStyle(.plain).help("\(title) (⌘\(index + 1))").accessibilityLabel(tr("Show \(title)", "查看\(title)"))
            .accessibilityAddTraits(tab == index ? .isSelected : [])
    }
    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: BrandIcon.menuBar()).renderingMode(.template).resizable().scaledToFit().frame(width: 26, height: 26)
                .foregroundStyle(palette.accent).accessibilityHidden(true)
            Text(tr("FlowCat", "流量喵")).font(.system(size: 14, weight: .semibold))
            Spacer()
            if monitor.diskTab { DiskStatusLabel(disk: monitor.disk, paused: monitor.paused) }
            else {
                PanelRecordingStatus(title: monitor.paused ? tr("Paused", "已暂停") : hasError ? tr("Sampling error", "采集异常") : monitor.lastSample == nil ? tr("Starting", "准备中") : tr("Recording", "记录中"),
                    warning: hasError, paused: monitor.paused)
            }
            DiskAlertBell(alerts: monitor.disk.alerts) { DiskAlertWindow.shared.show(monitor.disk); close() }
            Menu {
                Button(monitor.paused ? tr("Resume Recording", "继续记录") : tr("Pause Recording", "暂停记录")) { monitor.togglePause() }
                Divider()
                Menu(tr("Show in Menu Bar", "菜单栏显示")) {
                    Toggle(tr("Today's Total Traffic", "今日累计流量"), isOn: $monitor.showMenuBarTotal)
                    Toggle(tr("Network Speed", "实时网速"), isOn: $monitor.showMenuBarSpeed)
                    DiskSpeedToggle(disk: monitor.disk, title: tr("Disk Read/Write Speed", "磁盘读写速度"))
                }
                Toggle(tr("Include LAN in Totals", "总量包含局域网"), isOn: $monitor.includeLAN)
                Toggle(tr("Launch at Login", "登录时自动启动"), isOn: Binding(get: { monitor.loginEnabled }, set: { setLogin($0) }))
                Divider()
                Button(tr("Export Network CSV…", "导出网络 CSV…")) { monitor.export() }
                Button(tr("Export Disk CSV (\(monitor.disk.period.title))…", "导出磁盘 CSV（\(monitor.disk.period.title)）…")) { monitor.disk.export() }
                Button(tr("Disk Write Alerts…", "磁盘写入提醒…")) { DiskAlertWindow.shared.show(monitor.disk); close() }
                Divider()
                Button(tr("Settings…", "设置…")) { SettingsWindow.shared.show(monitor); close() }.keyboardShortcut(",")
                Button(tr("Check for Updates…", "检查更新…")) { UpdateChecker.shared.check() }
                Divider()
                Button(tr("Quit FlowCat", "退出流量喵")) { monitor.save(); NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 14, weight: .medium)).frame(width: 22, height: 26)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(tr("More", "更多操作"))
                .accessibilityLabel(tr("More", "更多操作"))
        }
    }
    private var filters: some View {
        HStack(spacing: 8) {
            PanelSegments(selection: $monitor.period,
                options: [(0, tr("Today", "今日")), (1, tr("Yesterday", "昨日")), (3, tr("7D", "7 天")), (2, tr("Month", "本月"))], label: tr("Period", "统计时间"),
                horizontalPadding: panelSize.width < 380 ? 7 : 9)
            Spacer(minLength: 0)
            PanelMenu(entries: networkEntries) {
                HStack(spacing: 6) {
                    if monitor.currentNetwork.identified && monitor.selectedNetwork == monitor.currentNetwork.name {
                        Image(systemName: "wifi").font(.system(size: 9))
                    }
                    Text(networkName).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                }.font(.system(size: 11)).foregroundStyle(palette.text)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(minWidth: 88, maxWidth: min(150, panelSize.width*0.36))
                    .background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border, lineWidth: 0.5))
            }.fixedSize(horizontal: false, vertical: true)
                .help(monitor.currentNetwork.identified ? tr("Filter by Wi-Fi name. Connected to \(monitor.currentNetwork.name)", "按 Wi-Fi 名称筛选；当前连接 \(monitor.currentNetwork.name)") : tr("Wi-Fi name unavailable; recording all networks only", "无法识别 Wi-Fi 名称时只记录全部网络"))
                .accessibilityLabel(tr("Network, \(networkName)", "统计网络，\(networkName)"))
        }
    }
    // The current Wi-Fi is listed first so the old tab-bar shortcut is no longer needed.
    private var networkEntries: [PanelMenuEntry] {
        var entries = [PanelMenuEntry(title: tr("All networks", "全部网络"), checked: monitor.selectedNetwork == "__all__") { monitor.selectedNetwork = "__all__" }]
        let current = monitor.currentNetwork.identified ? monitor.currentNetwork.name : nil
        if let current {
            entries.append(PanelMenuEntry(title: tr("\(current) (current)", "\(current)（当前连接）"), checked: monitor.selectedNetwork == current) { monitor.selectedNetwork = current })
        }
        for name in monitor.networkNames where name != current {
            entries.append(PanelMenuEntry(title: name, checked: monitor.selectedNetwork == name) { monitor.selectedNetwork = name })
        }
        return entries
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(spacing: 6) {
                Text(tr("\(periodName) total", "\(periodName)累计")).font(.system(size: 11, weight: .medium)).foregroundStyle(palette.secondary)
                if !monitor.includeLAN {
                    Text(tr("LAN excluded · estimate", "已扣除局域网 · 估算")).font(.system(size: 10)).foregroundStyle(palette.warning)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(palette.warningSurface).clipShape(Capsule())
                        .help(tr("Recognized LAN traffic is subtracted; short connections and protocol overhead may remain. Change it in the More menu or Settings.", "扣除已识别的局域网流量，可能遗漏短连接与协议开销。可在“更多”菜单或设置中切换。"))
                }
                Spacer()
                Text(coverageText(totalSeconds)).font(.system(size: 10)).foregroundStyle(palette.secondary).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                let parts = total.map { volume($0.total).split(separator: " ", maxSplits: 1).map(String.init) } ?? ["—"]
                Text(parts[0]).font(.system(size: compact ? 28 : 34, weight: .semibold, design: .rounded)).monospacedDigit()
                if parts.count > 1 { Text(parts[1]).font(.system(size: 16, weight: .medium)).foregroundStyle(palette.secondary) }
                Spacer()
            }.accessibilityElement(children: .ignore).accessibilityLabel("\(periodName) \(networkName) \(monitor.includeLAN ? tr("total", "总流量") : tr("total excluding LAN, estimate", "扣除局域网估算")) \(total.map { volume($0.total) } ?? tr("no data", "暂无记录"))")
            if let total {
                HStack(spacing: 18) {
                    metricLabel(tr("Down", "下载"), bytes: total.received, symbol: "arrow.down")
                    metricLabel(tr("Up", "上传"), bytes: total.sent, symbol: "arrow.up")
                }
            } else {
                Text(tr("No LAN-excluded estimate for this period yet.", "此时段还没有扣除局域网的估算记录。")).font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
            if !compact { trend }
            Rectangle().fill(palette.border).frame(height: 0.5)
            ViewThatFits(in: .horizontal) {
                HStack { liveTitle; Spacer(); liveRates }
                VStack(alignment: .leading, spacing: 5) { liveTitle; liveRates }
            }
        }.padding(compact ? 12 : 14).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    // Live rates always come from the physical interfaces, so say so only when totals exclude LAN.
    private var liveTitle: some View {
        Text(monitor.includeLAN ? tr("Network Speed", "实时网速") : tr("Network speed · incl. LAN", "实时网速 · 含局域网")).font(.system(size: 11)).foregroundStyle(palette.secondary)
    }
    private func amount(_ day: DayRecord) -> UInt64? {
        monitor.includeLAN ? (day.monitoredSeconds > 0 ? day.physical.total : nil) : day.withoutLAN?.bytes.total
    }
    private var trendPoints: [TrendPoint] {
        let calendar = Calendar.current, now = Date()
        if monitor.period <= 1 {
            let date = monitor.period == 0 ? now : calendar.date(byAdding: .day, value: -1, to: now)!
            let day = monitor.ledger.day(DateKeys.day(date), networkName: networkFilter)
            let hours = monitor.includeLAN ? day.hours ?? [:] : day.hoursWithoutLAN ?? [:]
            let start = calendar.startOfDay(for: date)
            return (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: start) }.map { hour in
                TrendPoint(label: hourLabel(hour), value: hours[String(Int(hour.timeIntervalSince1970))].map(\.total))
            }
        }
        var keys = DateKeys.keys(period: 3, now: now, available: [])
        if monitor.period == 2 {
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            keys = (0..<31).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.filter { $0 <= now }.map { DateKeys.day($0) }
        }
        return keys.map { TrendPoint(label: String($0.suffix(5)).replacingOccurrences(of: "-", with: "/"), value: amount(monitor.ledger.day($0, networkName: networkFilter))) }
    }
    private var trend: some View {
        TrendBars(points: trendPoints, trailingLabel: monitor.period <= 1 ? "24:00" : nil,
                  help: monitor.period <= 1 ? tr("Hourly traffic. Gray means no data; hourly history starts with version 1.7.", "每小时流量；灰色为未记录。小时数据从 1.7 起累计。") : tr("Daily traffic. Gray means no data.", "每日流量；灰色为未记录。"),
                  accessibility: tr("\(periodName) traffic trend; gray means no data", "\(periodName)流量趋势，灰色为未记录"))
    }
    private func metricLabel(_ title: String, bytes: UInt64, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.secondary)
            Text(title).font(.system(size: 11)).foregroundStyle(palette.secondary)
            Text(volume(bytes)).font(.system(size: 12, weight: .medium)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var liveRates: some View {
        HStack(spacing: 12) {
            Label("\(volume(UInt64(max(0, monitor.download))))/s", systemImage: "arrow.down")
            Label("\(volume(UInt64(max(0, monitor.upload))))/s", systemImage: "arrow.up")
        }.font(.system(size: 11, weight: .medium)).monospacedDigit()
    }
    private var processSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(showRelays ? tr("Proxies", "代理排行") : tr("Apps", "应用排行")).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                Text("\(rows.count)").font(.system(size: 11)).foregroundStyle(palette.secondary).monospacedDigit()
                InfoButton(text: showRelays
                    ? tr("Proxy and VPN counters include traffic relayed for other apps and local connections, so don't add them to the app ranking. Proxy history cannot be traced back to the original app.", "代理和 VPN 的计数包含其他应用经它转发的流量，以及本地连接，因此不要与应用排行相加。代理历史无法反推原始应用。")
                    : tr("App rankings come from per-process system counters, with recognizable helper processes merged. Proxy and VPN relays are listed separately. Rows don't add up to the machine total and are not a carrier bill.\n\n“Include LAN” only affects the total above; rankings always show full counters.", "应用排行来自系统进程计数，合并可识别的辅助进程。代理与 VPN 转发单独列出。各行相加不等于整机总量，也不代表运营商账单。\n\n“包含局域网”只影响上方总量，排行始终显示完整计数。"),
                    help: tr("About this ranking", "排行口径"))
                Spacer(minLength: 4)
                PanelSegments(selection: $showRelays, options: [(false, tr("Apps", "应用")), (true, tr("Proxies", "代理"))], label: tr("Ranking type", "排行类型"), horizontalPadding: 8)
                if compact { searchToggle }
                PanelSortMenu(selection: $order, options: [tr("Total", "总流量"), tr("Download", "下载量"), tr("Upload", "上传量")], label: tr("Sort by", "排序方式"))
            }
            if !compact || searchVisible || !search.isEmpty {
                PanelSearchField(text: $search, prompt: tr("Search processes", "搜索进程"), focusRequest: monitor.searchFocusRequest, autofocus: compact)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if rows.isEmpty { emptyState }
                    let top = Double(max(1, rows.first.map { metric($0.1) } ?? 1))
                    ForEach(rows, id: \.0) { row in
                        processRow(name: row.0, bytes: row.1, top: top)
                    }
                }
            }.frame(minHeight: 0, maxHeight: .infinity)
        }.frame(minHeight: 0, maxHeight: .infinity).layoutPriority(-1)
            .onChange(of: monitor.searchFocusRequest) { _ in searchVisible = true }
    }
    private var searchToggle: some View {
        Button { searchVisible.toggle(); if !searchVisible { search = "" } } label: {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(searchVisible ? palette.accent : palette.secondary)
                .frame(width: 18, height: 18).contentShape(Rectangle())
        }.buttonStyle(.plain).help(tr("Search processes (⌘F)", "搜索进程（⌘F）")).accessibilityLabel(tr("Search processes", "搜索进程"))
    }
    private func processRow(name: String, bytes: Bytes, top: Double) -> some View {
        let path = monitor.path(for: name)
        return RankRow(name: name, value: volume(metric(bytes)), fraction: Double(metric(bytes)) / top,
                subtitle: "↓\(volume(bytes.received))  ↑\(volume(bytes.sent))",
                badge: isRelay(name) ? tr("Relay", "转发") : nil, badgeHelp: tr("May include traffic relayed for other apps through a proxy or VPN; don't add it to those apps", "可能包含其他程序经代理或 VPN 转发的流量，不应与原程序相加"),
                actions: [PanelMenuEntry(title: tr("Show in Finder", "打开位置"), enabled: path != nil) { if let path { ProcessLocation.reveal(path.path) } }]) {
            processIcon(name).onAppear { monitor.loadIcon(name) }
        } detail: { EmptyView() }
    }
    @ViewBuilder private func processIcon(_ name: String) -> some View {
        if isRelay(name) {
            FallbackIcon(name: name, symbol: "point.3.connected.trianglepath.dotted")
        } else if ["ssh", "node", "java", "python", "codex", "claude"].contains(where: { name.lowercased().hasPrefix($0) }) {
            FallbackIcon(name: name, symbol: "terminal")
        } else if let icon = monitor.icons[name] {
            Image(nsImage: icon).resizable().interpolation(.high).clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            FallbackIcon(name: name)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: search.isEmpty ? "chart.bar" : "magnifyingglass").font(.system(size: 23)).foregroundStyle(palette.secondary)
            Text(!search.isEmpty ? tr("No matching processes", "没有匹配的进程") : monitor.paused ? tr("Recording is paused", "统计已暂停") : hasError ? tr("Traffic is temporarily unavailable", "暂时无法读取流量") : monitor.lastSample == nil ? tr("Building a baseline", "正在建立统计基线") : showRelays ? tr("No recognized proxy traffic in this period", "这个时段没有已识别的代理记录") : tr("No app traffic in this period yet", "这个时段还没有应用记录"))
                .font(.system(size: 12, weight: .medium))
            Text(!search.isEmpty ? tr("Try part of the process name.", "试试进程名称的一部分。") : tr("Traffic is counted while FlowCat runs; earlier history cannot be recovered.", "流量从工具运行后累计，未运行的历史无法补算。"))
                .font(.system(size: 11)).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
            if !search.isEmpty { Button(tr("Clear Search", "清除搜索")) { search = "" }.controlSize(.small) }
            else if monitor.paused { Button(tr("Resume Recording", "继续记录")) { monitor.togglePause() }.controlSize(.small) }
            else if hasError { Button(tr("Sample Again", "重新采集")) { monitor.sample() }.controlSize(.small) }
            else if monitor.selectedNetwork != "__all__" { Button(tr("Show All Networks", "查看全部网络")) { monitor.selectedNetwork = "__all__" }.controlSize(.small) }
        }.frame(maxWidth: .infinity).padding(.vertical, 24).padding(.horizontal, 14)
    }
    private var errorBanner: some View {
        Label(monitor.status, systemImage: "exclamationmark.circle")
            .font(.system(size: 11)).lineLimit(2).help(monitor.status)
            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(palette.border).frame(height: 0.5)
            HStack {
                InfoButton(title: tr("How it's counted", "统计说明"), text: tr("Totals come from the physical network interfaces and include LAN traffic, so they are not a carrier bill. Apps and proxy relays are listed separately; both are per-process counters and should not be added together. Proxy history cannot be traced back to the original app, and a missing app row does not mean no traffic.\n\n“Include LAN in totals” lives in the More menu and Settings and only affects totals. When off, recognized LAN bytes from the same sampling interval are subtracted, clamping download and upload at zero separately. Short connections, protocol overhead and traffic inside a VPN may remain, so the result is an estimate. Estimates start with 1.5.4 and hourly trends with 1.7; older history is unchanged.\n\nSamples every 10 seconds and saves every minute. When the network cannot be identified, only “All networks” is recorded.\n\nRecording since: ", "整机总量来自物理网卡，包含局域网流量，不等于运营商账单。应用与代理转发分开展示，均为进程计数，请勿相加。代理历史无法反推原始应用；没有应用记录不表示没有流量。\n\n“总量包含局域网”可在“更多”菜单或设置中切换，只控制总量。关闭后，从同一采样区间的网卡计数中扣除已识别的局域网连接字节；下载、上传分别归零截断。短连接、协议开销及 VPN 内部流量可能无法剔除，结果是估算。估算从 1.5.4 起累计，小时趋势从 1.7 起累计，旧历史保持原值。\n\n每 10 秒采样，每分钟保存。网络无法识别时只记录全部。\n\n开始记录：") + appDate(monitor.ledger.firstStarted, date: .numeric, time: .shortened))
                Spacer()
                Button { monitor.export() } label: { Label(tr("Export CSV", "导出 CSV"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderless).help(tr("Export all network history", "导出全部网络历史"))
            }.font(.system(size: 11)).foregroundStyle(palette.secondary)
            if !loginError.isEmpty {
                Text(loginError).font(.system(size: 11)).foregroundStyle(palette.warning)
            }
        }
    }
    private func isRelay(_ name: String) -> Bool {
        ProcessTraffic.isRelay(name)
    }
    private func setLogin(_ enabled: Bool) {
        do {
            try monitor.setLogin(enabled)
            loginError = ""
        } catch {
            loginError = tr("Move FlowCat to the Applications folder first.", "请先把应用放入“应用程序”，再设置登录启动。")
        }
    }
}
