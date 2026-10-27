import AppKit
import SwiftUI

struct DiskStatusLabel: View {
    @ObservedObject var disk: DiskMonitor
    var paused: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PanelRecordingStatus(title: paused ? tr("Paused", "已暂停") : !disk.samplingError.isEmpty ? tr("Sampling error", "采集异常") : disk.lastSample == nil ? tr("Starting", "准备中") : tr("Recording", "记录中"),
            warning: !disk.samplingError.isEmpty, paused: paused)
    }
}
struct DiskSpeedToggle: View {
    @ObservedObject var disk: DiskMonitor
    var title = tr("Show disk speed in menu bar", "菜单栏显示磁盘读写")
    var body: some View { Toggle(title, isOn: $disk.showMenuBarDiskSpeed) }
}
// Alerts apply to both tabs, so the entry sits in the header with a dot for today's alerts.
struct DiskAlertBell: View {
    @ObservedObject var alerts: DiskAlertController
    var open: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = Palette(dark: scheme == .dark)
        let today = alerts.memory.recent.filter { Calendar.current.isDateInToday($0.date) }.count
        let help = !alerts.preferences.enabled ? tr("Disk write alerts: off", "磁盘写入提醒：未开启") : today > 0 ? tr("Disk write alerts: \(today) today", "磁盘写入提醒：今日 \(today) 条") : tr("Disk write alerts: on", "磁盘写入提醒：已开启")
        Button(action: open) {
            Image(systemName: alerts.preferences.enabled ? "bell" : "bell.slash").font(.system(size: 12))
                .foregroundStyle(palette.secondary).frame(width: 24, height: 26)
                .overlay(alignment: .topTrailing) {
                    if today > 0 { Circle().fill(palette.warning).frame(width: 7, height: 7).offset(x: -3, y: 5) }
                }.contentShape(Rectangle())
        }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}
struct DiskView: View {
    @ObservedObject var disk: DiskMonitor
    @ObservedObject var monitor: TrafficMonitor
    var panelSize: CGSize
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var l10n = Localization.shared
    @ViewState private var search = ""
    @ViewState private var searchVisible = false
    @ViewState private var sort = 0
    @ViewState private var calendarOpen = false
    @ViewState private var expanded: Set<String> = []
    private var palette: Palette { Palette(dark: scheme == .dark) }
    private var compact: Bool { panelSize.height < 540 }
    private func value(_ b: DiskBytes) -> UInt64 { sort == 0 ? b.written : sort == 1 ? b.read : b.total }
    var body: some View {
        VStack(spacing: compact ? 8 : 10) {
            if disk.healthView { health }
            else { statistics }
            footer
        }.frame(minHeight: 0, maxHeight: .infinity)
            .onAppear { disk.sample(); if disk.healthView { disk.refreshHealth() } }
            .onChange(of: disk.healthView) { if $0 { disk.refreshHealth() } }
    }
    private var statistics: some View {
        let record = disk.selected
        return VStack(spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                PanelSegments(selection: $disk.period, options: periodOptions, label: tr("Disk period", "磁盘统计周期"),
                              horizontalPadding: panelSize.width < 380 ? 6 : 8)
                Spacer(minLength: 0)
                dayStepper
            }
            summary(record)
            if !disk.storageError.isEmpty { banner(disk.storageError) }
            if !disk.samplingError.isEmpty { banner(disk.samplingError) }
            processList(record)
        }.frame(minHeight: 0, maxHeight: .infinity)
    }
    // A picked day appears as its own segment so the selection is always visible.
    private var periodOptions: [(DiskPeriod, String)] {
        var options: [(DiskPeriod, String)] = [(.today, tr("Today", "今日")), (.seven, tr("7D", "7 天")), (.thirty, tr("30D", "30 天")), (.all, tr("All", "累计"))]
        if disk.period == .date { options.append((.date, disk.selectedDate.formatted(.dateTime.month(.defaultDigits).day().locale(appLocale)))) }
        return options
    }
    private var periodTitle: String {
        disk.period == .date ? disk.selectedDate.formatted(.dateTime.month().day().locale(appLocale)) : disk.period.title
    }
    private var shownDay: Date { disk.period == .date ? disk.selectedDate : Date() }
    private func canStep(_ offset: Int) -> Bool {
        let calendar = Calendar.current
        if offset > 0 { return disk.period == .date }
        return calendar.startOfDay(for: shownDay) > calendar.startOfDay(for: disk.historyStart)
            || disk.period != .date && disk.period != .today
    }
    private func show(day: Date) {
        if Calendar.current.isDateInToday(day) { disk.period = .today }
        else { disk.selectedDate = day; disk.period = .date }
    }
    private func step(_ offset: Int) {
        let base = disk.period == .date || disk.period == .today ? shownDay : Date()
        let next = Calendar.current.date(byAdding: .day, value: offset, to: base) ?? base
        show(day: disk.period == .date || disk.period == .today ? next : Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? next)
    }
    private var dayStepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", help: tr("Previous day", "前一天"), enabled: canStep(-1)) { step(-1) }
            Button { calendarOpen.toggle() } label: {
                Image(systemName: "calendar").frame(width: 24, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain).help(tr("Pick a day", "按日查看")).accessibilityLabel(tr("Choose a day to view disk activity", "选择日期查看磁盘读写"))
                .popover(isPresented: $calendarOpen) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tr("View a single day", "按日查看读写")).font(.headline)
                        DatePicker(tr("Date", "日期"), selection: Binding(get: { shownDay }, set: { show(day: $0); calendarOpen = false }),
                                   in: disk.historyStart...Date(), displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden()
                    }.padding(16)
                }
            stepButton("chevron.right", help: tr("Next day", "后一天"), enabled: canStep(1)) { step(1) }
        }.font(.system(size: 11)).foregroundStyle(palette.text)
            .background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border, lineWidth: 0.5))
    }
    private func stepButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).frame(width: 20, height: 22).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.35).help(help).accessibilityLabel(help)
    }
    private func summary(_ record: DiskDay) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 7) {
            HStack {
                Text(tr("\(periodTitle) · process writes", "\(periodTitle)进程写入"))
                Spacer()
                Text(coverageText(record.seconds)).monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                let parts = diskVolume(record.bytes.written).split(separator: " ", maxSplits: 1)
                Text(String(parts[0])).font(.system(size: compact ? 28 : 34, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(parts.count > 1 ? String(parts[1]) : "B").font(.system(size: 16, weight: .medium)).foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                Text(tr("Read \(diskVolume(record.bytes.read))", "读取 \(diskVolume(record.bytes.read))"))
                Text(tr("Total \(diskVolume(record.bytes.total))", "总读写 \(diskVolume(record.bytes.total))"))
            }.font(.system(size: 11)).foregroundStyle(palette.secondary).monospacedDigit()
            if !compact { trend }
            Rectangle().fill(palette.border).frame(height: 0.5)
            ViewThatFits(in: .horizontal) {
                HStack { Text(tr("Live disk activity", "实时读写")); Spacer(); rates }
                VStack(alignment: .leading, spacing: 4) { Text(tr("Live disk activity", "实时读写")); rates }
            }.font(.system(size: 11)).foregroundStyle(palette.secondary)
        }.padding(compact ? 12 : 14).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var rates: some View {
        Text(monitor.paused ? tr("Paused", "已暂停") : tr("R ", "读 ") + "\(diskVolume(UInt64(max(0,disk.readRate))))/s  " + tr("W ", "写 ") + "\(diskVolume(UInt64(max(0,disk.writeRate))))/s")
            .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(palette.text).fixedSize()
    }
    private var chartPoints: [TrendPoint] {
        let calendar = Calendar.current
        if disk.period == .today || disk.period == .date {
            let date = disk.period == .today ? Date() : disk.selectedDate
            let key = DateKeys.day(date), start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
            var points: [TrendPoint] = [], cursor = start
            while cursor < end {
                let hour = String(Int(cursor.timeIntervalSince1970))
                points.append(TrendPoint(label: hourLabel(cursor), value: disk.ledger.days[key]?.hours[hour]?.bytes.written))
                guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor), next > cursor else { break }; cursor = next
            }
            return points
        }
        var keys = disk.keys
        if disk.period == .all {
            let start = max(calendar.startOfDay(for: disk.historyStart), calendar.date(byAdding: .day, value: -59, to: Date())!)
            var cursor = calendar.startOfDay(for: start); keys = []
            while cursor <= Date() {
                keys.append(DateKeys.day(cursor))
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }; cursor = next
            }
        }
        return keys.map { key in TrendPoint(label: String(key.suffix(5)).replacingOccurrences(of: "-", with: "/"), value: disk.ledger.days[key]?.bytes.written) }
    }
    private var trend: some View {
        TrendBars(points: chartPoints, trailingLabel: disk.period == .today || disk.period == .date ? "24:00" : nil,
                  help: disk.period == .all ? tr("Writes over the last 60 days at most. Gray means no data; the total covers all history.", "最近最多 60 天的写入趋势；灰色为未记录。累计总量包含全部历史。") : tr("Write trend. Gray means no data.", "写入趋势；灰色时段没有记录。"),
                  accessibility: tr("Write trend; gray means no data.", "写入趋势，灰色时段没有记录。"), format: diskVolume)
    }
    private func processList(_ record: DiskDay) -> some View {
        let rows = record.processes.sorted { a,b in value(a.value.bytes) == value(b.value.bytes) ? a.key < b.key : value(a.value.bytes) > value(b.value.bytes) }
            .filter { search.isEmpty || $0.value.name.localizedCaseInsensitiveContains(search) || $0.value.path.localizedCaseInsensitiveContains(search) }
        let top = Double(max(1, rows.first.map { value($0.value.bytes) } ?? 1))
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(tr("Processes", "进程排行")).font(.system(size: 12, weight: .semibold))
                Text("\(rows.count)").font(.system(size: 11)).foregroundStyle(palette.secondary).monospacedDigit()
                InfoButton(text: tr("Reads and writes come from per-process system counters across all disks. Apps are merged with their helpers, and exited processes keep what was sampled. Click a row to see its path.", "读写量来自进程的系统计数器增量，覆盖所有磁盘；应用与其辅助进程合并，已退出进程保留已采集记录。点击一行查看路径。")
                    + (disk.denied > 0 ? tr("\n\n\(disk.sampledProcesses) processes are readable and \(disk.denied) are restricted by macOS; only sampled data is shown.", "\n\n当前 \(disk.sampledProcesses) 个进程可采集，\(disk.denied) 个受系统权限限制，只展示已采集数据。") : ""),
                    help: tr("About this ranking", "排行口径"))
                Spacer()
                if compact {
                    Button { searchVisible.toggle(); if !searchVisible { search = "" } } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(searchVisible ? palette.accent : palette.secondary)
                            .frame(width: 18, height: 18).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(tr("Search processes (⌘F)", "搜索进程（⌘F）")).accessibilityLabel(tr("Search processes", "搜索进程"))
                }
                PanelSortMenu(selection: $sort, options: [tr("Writes", "写入量"), tr("Reads", "读取量"), tr("Total", "总读写")], label: tr("Sort processes", "磁盘排行排序"))
            }
            if !compact || searchVisible || !search.isEmpty {
                PanelSearchField(text: $search, prompt: tr("Search apps or processes", "搜索应用或进程"), focusRequest: monitor.searchFocusRequest, autofocus: compact)
            }
            ScrollView {
                if rows.isEmpty { emptyRecords(record) }
                else {
                    LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.key) { row in processRow(id: row.key, process: row.value, top: top) }
                    }
                }
            }.frame(minHeight: 0, maxHeight: .infinity)
        }.frame(minHeight: 0, maxHeight: .infinity).layoutPriority(-1)
            .onChange(of: monitor.searchFocusRequest) { _ in searchVisible = true }
    }
    private func processRow(id: String, process: DiskProcessUsage, top: Double) -> some View {
        let available = ProcessLocation.existingURL(process.path) != nil
        return RankRow(name: process.name, value: diskVolume(value(process.bytes)), fraction: Double(value(process.bytes)) / top,
                subtitle: tr("R ", "读 ") + diskVolume(process.bytes.read) + "  " + tr("W ", "写 ") + diskVolume(process.bytes.written),
                actions: [PanelMenuEntry(title: tr("Show in Finder", "打开位置"), enabled: available) { ProcessLocation.reveal(process.path) },
                          PanelMenuEntry(title: tr("Write Alert Settings…", "写入提醒设置…")) { disk.alerts.selectedPath = process.path; DiskAlertWindow.shared.show(disk) }],
                expanded: expanded.contains(id),
                toggle: { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } }) {
            Group {
                if let icon = monitor.icons[process.name] { Image(nsImage: icon).resizable().scaledToFit() }
                else { FallbackIcon(name: process.name, symbol: process.path.hasSuffix(".app") ? nil : "terminal") }
            }.onAppear { monitor.loadDiskIcon(process.name, path: process.path) }
        } detail: {
            VStack(alignment: .leading, spacing: 4) {
                Text(process.path).textSelection(.enabled)
                Text(process.path.hasSuffix(".app") ? tr("App merged with its helper processes; covers all disks.", "应用与其辅助进程合并；覆盖所有磁盘。") : tr("System process counter; covers all disks.", "系统进程计数；覆盖所有磁盘。"))
            }.font(.system(size: 10)).foregroundStyle(palette.secondary)
        }
    }
    private func emptyRecords(_ record: DiskDay) -> some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "internaldrive" : "magnifyingglass").font(.system(size: 22)).foregroundStyle(palette.secondary)
            Text(!search.isEmpty ? tr("No matching processes", "没有匹配的进程") : monitor.paused ? tr("Recording is paused", "统计已暂停") : record.seconds > 0 ? tr("No process activity sampled in this period", "此时段未采集到进程读写") : tr("No disk activity recorded for this period yet", "这个时段还没有读写记录"))
                .font(.system(size: 12, weight: .medium))
            Text(search.isEmpty ? tr("Counted since monitoring started; earlier history cannot be recovered, and missing data does not mean zero activity.", "从开启监控后累计，历史无法补算；缺失记录不表示实际读写为零。") : tr("Try another name or clear the search.", "换个名称搜索，或清除筛选。"))
                .font(.system(size: 11)).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
            if !search.isEmpty { Button(tr("Clear Search", "清除搜索")) { search = "" }.controlSize(.small) }
            else if monitor.paused { Button(tr("Resume Recording", "继续记录")) { monitor.togglePause() }.controlSize(.small) }
            else if !disk.samplingError.isEmpty { Button(tr("Try Again", "重试采集")) { disk.sample() }.controlSize(.small) }
        }.padding(18).frame(maxWidth: .infinity)
    }
    private var health: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if disk.healthLoading {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(tr("Reading disk information…", "正在读取磁盘信息…")).font(.system(size: 11)) }.foregroundStyle(palette.secondary)
                }
                if !disk.healthError.isEmpty {
                    banner(disk.healthError)
                    Button(tr("Read Again", "重新读取")) { disk.refreshHealth(force: true) }.controlSize(.small)
                }
                if let device = disk.device {
                    HStack(spacing: 8) {
                        Image(systemName: device.internalDisk ? "internaldrive" : "externaldrive").font(.system(size: 23)).foregroundStyle(palette.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle).help(device.name)
                            Text("\(device.internalDisk ? tr("Internal", "内置") : tr("External", "外置")) \(device.solidState ? "SSD" : tr("disk", "磁盘")) · \(diskVolume(device.capacity))")
                                .font(.system(size: 10)).foregroundStyle(palette.secondary)
                        }
                        Spacer(minLength: 4)
                        // Only offer a picker when there is something to pick.
                        if disk.devices.count > 1 {
                            PanelMenu(entries: disk.devices.map { item in
                                PanelMenuEntry(title: "\(item.name) (\(item.internalDisk ? tr("internal", "内置") : tr("external", "外置")))", checked: item.id == device.id) { disk.selectedDevice = item.id }
                            }) {
                                HStack(spacing: 6) {
                                    Text(tr("Switch Disk", "切换磁盘"))
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                                }.font(.system(size: 11)).foregroundStyle(palette.text)
                                    .padding(.horizontal, 8).padding(.vertical, 5).background(palette.track)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }.fixedSize().accessibilityLabel(tr("Choose a physical disk, \(disk.devices.count) available", "选择物理磁盘，共 \(disk.devices.count) 块"))
                        }
                    }
                    healthHero(device)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            cell(tr("Temperature", "温度"), device.temperature.map { "\($0) °C" })
                            Rectangle().fill(palette.border).frame(width: 0.5)
                            cell(tr("Lifetime host writes", "累计主机写入"), device.hostWritten.map(diskVolume))
                        }.fixedSize(horizontal: false, vertical: true)
                        Rectangle().fill(palette.border).frame(height: 0.5)
                        HStack(spacing: 0) {
                            cell(tr("Power-on time", "通电时间"), device.powerOnHours.map { "\($0.formatted()) " + tr("hours", "小时") })
                            Rectangle().fill(palette.border).frame(width: 0.5)
                            cell(tr("Media & integrity errors", "介质与数据完整性错误"), device.mediaErrors.map { $0.formatted() })
                        }.fixedSize(horizontal: false, vertical: true)
                    }.background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(palette.border, lineWidth: 0.5))
                    Text(tr("Details", "磁盘详情")).font(.system(size: 12, weight: .semibold)).padding(.top, 2)
                    if !device.model.isEmpty && device.model != device.name { fact(tr("Model", "型号"), device.model) }
                    fact(tr("Available spare", "可用备用空间"), device.availableSpare.map { "\($0)%" } ?? tr("Not provided", "未提供"))
                    fact(tr("Lifetime host reads", "累计主机读取"), device.hostRead.map(diskVolume) ?? tr("Not provided", "未提供"))
                } else if !disk.healthLoading && disk.healthError.isEmpty {
                    VStack(spacing: 10) {
                        Text(tr("No physical disks found", "没有找到物理磁盘")).font(.system(size: 13, weight: .medium))
                        Button(tr("Detect Again", "重新检测")) { disk.refreshHealth(force: true) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 36)
                }
            }.padding(.trailing, 2)
        }.frame(minHeight: 0, maxHeight: .infinity)
    }
    private func healthHero(_ device: DiskDevice) -> some View {
        let title: String
        switch device.status {
        case .normal: title = tr("Drive is healthy", "磁盘运行正常")
        case .warning: title = tr("Drive reports a hardware warning", "磁盘报告硬件警告")
        case .unavailable: title = tr("Health data not provided", "健康信息未提供")
        case .permission: title = tr("Health data access restricted", "健康信息访问受限")
        case .failed: title = tr("Health data temporarily unavailable", "暂时无法读取健康信息")
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                Label(device.status == .normal ? tr("SMART OK", "SMART 正常") : device.status == .warning ? tr("Attention", "需关注") : tr("Not read", "未读取"),
                      systemImage: device.status == .normal ? "checkmark.circle" : device.status == .warning ? "exclamationmark.triangle" : "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(device.status == .normal ? palette.success : device.status == .warning ? palette.warning : palette.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(device.status == .normal ? palette.successSurface : device.status == .warning ? palette.warningSurface : palette.track)
                    .clipShape(Capsule()).fixedSize()
            }
            Text(device.message).font(.system(size: 11)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            if let used = device.enduranceUsed {
                HStack { Text(tr("Rated endurance used", "额定耐久度已用")); Spacer(); Text("\(used)%").fontWeight(.semibold).monospacedDigit() }.font(.system(size: 11)).padding(.top, 4)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.accent).frame(width: geometry.size.width*CGFloat(min(100,max(0,used)))/100)
                    }
                }.frame(height: 4)
                Text(tr("The drive's own endurance estimate, not remaining life.", "磁盘提供的耐久度估算，不代表剩余寿命。"))
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
            if device.status == .failed { Button(tr("Retry", "重试")) { disk.refreshHealth(force: true) }.controlSize(.small) }
        }.padding(14).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func cell(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11)).foregroundStyle(palette.secondary).lineLimit(2)
            if let value {
                let parts = value.split(separator: " ", maxSplits: 1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(parts[0])).font(.system(size: 19, weight: .semibold)).monospacedDigit()
                    if parts.count > 1 { Text(String(parts[1])).font(.system(size: 11)).foregroundStyle(palette.secondary) }
                }.lineLimit(1).minimumScaleFactor(0.8)
            } else { Text(tr("Not provided", "未提供")).font(.system(size: 13, weight: .semibold)) }
        }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(12)
    }
    private func fact(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title).foregroundStyle(palette.secondary).fixedSize()
                Spacer(minLength: 0)
                Text(value).lineLimit(2).multilineTextAlignment(.trailing).help(value)
            }.font(.system(size: 11))
            Rectangle().fill(palette.border).frame(height: 0.5)
        }
    }
    private func banner(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .padding(8).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(palette.border).frame(height: 0.5)
            HStack(spacing: 10) {
                if disk.healthView {
                    InfoButton(title: tr("About this data", "数据说明"), text: tr("Health data is read natively from the SMART information macOS and IOKit provide, on demand and then about every 10 minutes. FlowCat never runs a self-test or changes hardware settings. Drives and enclosures expose different fields; missing ones show “Not provided”, and some external enclosures provide none.\n\n“Rated endurance used” is the drive's own estimate, not remaining life. Lifetime host reads and writes are shown separately from the process activity FlowCat recorded.", "健康信息原生读取系统与 IOKit 提供的 SMART 数据，按需读取，之后约每 10 分钟刷新；不进行磁盘自检，也不修改硬件设置。不同硬盘和连接提供的字段不同，缺少的指标显示“未提供”；外置硬盘盒可能不提供健康信息。\n\n耐久度已用是磁盘自身的估算，不代表剩余寿命。硬件累计读写与流量喵记录期间的进程统计分开展示。"))
                    Spacer()
                    if let device = disk.device { (Text(tr("Updated ", "更新于 ")) + Text(device.updated, style: .time)).monospacedDigit() }
                    Button(tr("Refresh", "刷新")) { disk.refreshHealth(force: true) }.buttonStyle(.borderless).disabled(disk.healthLoading)
                } else {
                    InfoButton(title: tr("How it's counted", "统计口径"), text: tr("Process reads and writes come from system counter deltas across all disks, with app helpers merged. They are not the physical NAND writes inside an SSD and are not used to estimate lifespan. Short-lived processes, permissions and shared I/O affect attribution; nothing is forced onto an app.\n\n7 and 30 days include today; All time starts when recording began. Only sampled time is counted — sleep, pauses and missed samples are not filled with zeros.\n\nRecording since: ", "进程读写来自系统计数器增量，覆盖所有磁盘，应用辅助进程合并。它不等于 SSD 闪存物理写入，也不用于推算寿命。短暂进程、权限及共享 I/O 会影响归属；不强行归到应用。\n\n7 天、30 天包含今日，累计自开始记录起算。仅统计运行期间的采样，睡眠、暂停和漏采不补零。\n\n开始记录：") + appDate(disk.ledger.firstStarted, date: .numeric, time: .shortened))
                    Spacer()
                    Button { disk.export() } label: { Label(tr("Export CSV", "导出 CSV"), systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderless).help(tr("Export disk activity for the current period", "导出当前时段的磁盘读写"))
                }
            }.font(.system(size: 11)).foregroundStyle(palette.secondary)
        }
    }
}
