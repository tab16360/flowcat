import AppKit
import SwiftUI

struct DiskModePicker: View {
    @ObservedObject var disk: DiskMonitor
    var body: some View {
        PanelSegments(selection: $disk.healthView, options: [(false, "读写统计"), (true, "磁盘状态")], label: "磁盘视图")
    }
}
struct DiskStatusLabel: View {
    @ObservedObject var disk: DiskMonitor
    var paused: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        PanelRecordingStatus(title: paused ? "已暂停" : !disk.samplingError.isEmpty ? "采集异常" : disk.lastSample == nil ? "准备中" : "记录中",
            warning: !disk.samplingError.isEmpty, paused: paused)
    }
}
struct DiskSpeedToggle: View {
    @ObservedObject var disk: DiskMonitor
    var body: some View { Toggle("菜单栏显示磁盘读写", isOn: $disk.showMenuBarDiskSpeed) }
}
struct DiskView: View {
    @ObservedObject var disk: DiskMonitor
    @ObservedObject var monitor: TrafficMonitor
    var panelSize: CGSize
    @Environment(\.colorScheme) private var scheme
    @ViewState private var search = ""
    @ViewState private var sort = 0
    @ViewState private var explanation = false
    @ViewState private var calendarOpen = false
    @ViewState private var expanded: Set<String> = []
    private var palette: Palette { Palette(dark: scheme == .dark) }
    private var compact: Bool { panelSize.height < 540 }
    private func value(_ b: DiskBytes) -> UInt64 { sort == 0 ? b.written : sort == 1 ? b.read : b.total }
    var body: some View {
        VStack(spacing: 10) {
            if disk.healthView { health }
            else { statistics }
            footer
        }.frame(minHeight: 0, maxHeight: .infinity)
            .onAppear { disk.sample(); if disk.healthView { disk.refreshHealth() } }
            .onChange(of: disk.healthView) { if $0 { disk.refreshHealth() }; explanation = false }
    }
    private var statistics: some View {
        let record = disk.selected
        return VStack(spacing: 10) {
            HStack(spacing: 8) {
                PanelSegments(selection: $disk.period,
                    options: [(DiskPeriod.today, "今日"), (.seven, "7 天"), (.thirty, "30 天"), (.all, "累计")], label: "磁盘统计周期")
                Spacer(minLength: 0)
                Button { calendarOpen.toggle() } label: {
                    HStack(spacing: 6) {
                        Text(DateKeys.day(disk.period == .date ? disk.selectedDate : Date()).replacingOccurrences(of: "-", with: "/")).monospacedDigit()
                        Image(systemName: "calendar")
                    }.font(.system(size: 11)).foregroundStyle(palette.text)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border, lineWidth: 0.5))
                }.buttonStyle(.plain).accessibilityLabel("按日查看磁盘读写")
                    .popover(isPresented: $calendarOpen) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("查看每日读写").font(.headline)
                            DatePicker("日期", selection: $disk.selectedDate, in: disk.historyStart...Date(), displayedComponents: .date)
                                .datePickerStyle(.graphical).labelsHidden()
                            Button("查看这一天") { disk.period = .date; calendarOpen = false }
                                .buttonStyle(.borderedProminent)
                        }.padding(16)
                    }
            }
            summary(record)
            if !disk.storageError.isEmpty { banner(disk.storageError) }
            if !disk.samplingError.isEmpty { banner(disk.samplingError) }
            processList(record)
        }.frame(minHeight: 0, maxHeight: .infinity)
    }
    private func coverage(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        if value < 60 { return "已记录 \(value) 秒" }
        if value < 3600 { return "已记录 \(value/60) 分" }
        return "已记录 \(value/3600) 小时 \((value%3600)/60) 分"
    }
    private func summary(_ record: DiskDay) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(disk.period.title)进程写入")
                Spacer()
                Text(coverage(record.seconds)).monospacedDigit()
            }.font(.system(size: 11)).foregroundStyle(palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                let parts = diskVolume(record.bytes.written).split(separator: " ", maxSplits: 1)
                Text(String(parts[0])).font(.system(size: 32, weight: .semibold)).monospacedDigit()
                Text(parts.count > 1 ? String(parts[1]) : "B").font(.system(size: 14, weight: .medium)).foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                Text("读取 \(diskVolume(record.bytes.read))")
                Text("总读写 \(diskVolume(record.bytes.total))")
            }.font(.system(size: 11)).foregroundStyle(palette.secondary).monospacedDigit()
            if !compact { trend }
            Rectangle().fill(palette.border).frame(height: 0.5)
            ViewThatFits(in: .horizontal) {
                HStack { Text("实时 · 已采集进程"); Spacer(); rates }
                VStack(alignment: .leading, spacing: 4) { Text("实时 · 已采集进程"); rates }
            }.font(.system(size: 11)).foregroundStyle(palette.secondary)
        }.padding(12).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var rates: some View {
        Text(monitor.paused ? "已暂停" : "读 \(diskVolume(UInt64(max(0,disk.readRate))))/s  写 \(diskVolume(UInt64(max(0,disk.writeRate))))/s")
            .font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(palette.text).fixedSize()
    }
    private var chartPoints: [(String, DiskBucket?)] {
        let calendar = Calendar.current
        if disk.period == .today || disk.period == .date {
            let date = disk.period == .today ? Date() : disk.selectedDate
            let key = DateKeys.day(date), start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
            var points: [(String, DiskBucket?)] = [], cursor = start
            while cursor < end {
                let hour = String(Int(cursor.timeIntervalSince1970))
                points.append((cursor.formatted(.dateTime.hour().minute()), disk.ledger.days[key]?.hours[hour]))
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
        return keys.map { key in (String(key.suffix(5)), disk.ledger.days[key].map { DiskBucket(bytes: $0.bytes, seconds: $0.seconds) }) }
    }
    private var trend: some View {
        let points = chartPoints, maxValue = max(1, points.compactMap { $0.1?.bytes.written }.max() ?? 1)
        return VStack(spacing: 3) {
            GeometryReader { geometry in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        let height = CGFloat(Double(point.1?.bytes.written ?? 0) / Double(maxValue)) * geometry.size.height
                        RoundedRectangle(cornerRadius: 1)
                            .fill(point.1 == nil ? palette.track : palette.accent)
                            .frame(height: max(1, height))
                            .help("\(point.0)：\(point.1.map { diskVolume($0.bytes.written) } ?? "未记录")")
                    }
                }.frame(maxHeight: .infinity, alignment: .bottom)
            }.frame(height: 28)
            HStack {
                Text(points.first?.0 ?? "")
                Spacer()
                Text(points.isEmpty ? "" : points[points.count/2].0)
                Spacer()
                Text(disk.period == .today || disk.period == .date ? "24:00" : points.last?.0 ?? "")
            }.font(.system(size: 10)).foregroundStyle(palette.secondary)
        }.padding(.top, 4).help(disk.period == .all ? "最近最多 60 天的写入趋势；灰色为未记录。累计总量包含全部历史。" : "写入趋势；灰色时段没有记录。")
            .accessibilityElement(children: .ignore).accessibilityLabel("写入趋势，灰色时段没有记录。可移动指针查看各时段写入量。")
    }
    private func processList(_ record: DiskDay) -> some View {
        let rows = record.processes.sorted { a,b in value(a.value.bytes) == value(b.value.bytes) ? a.key < b.key : value(a.value.bytes) > value(b.value.bytes) }
            .filter { search.isEmpty || $0.value.name.localizedCaseInsensitiveContains(search) || $0.value.path.localizedCaseInsensitiveContains(search) }
        return VStack(spacing: 7) {
            HStack {
                Text("进程排行").font(.system(size: 12, weight: .semibold))
                Text("\(rows.count)").font(.system(size: 10)).foregroundStyle(palette.secondary)
                Spacer()
                if disk.denied > 0 {
                    Image(systemName: "info.circle").font(.system(size: 10)).foregroundStyle(palette.secondary)
                        .help("\(disk.sampledProcesses) 个进程可采集，\(disk.denied) 个进程受系统权限限制；只展示已采集数据。")
                        .accessibilityLabel("部分进程受权限限制，\(disk.sampledProcesses) 个可采集，\(disk.denied) 个不可读")
                }
                PanelMenu(entries: [("写入量", { sort = 0 }), ("读取量", { sort = 1 }), ("总读写", { sort = 2 })]) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                        Text(["写入量", "读取量", "总读写"][sort])
                        Image(systemName: "chevron.down").font(.system(size: 8))
                    }.font(.system(size: 11)).foregroundStyle(palette.secondary)
                }.fixedSize().accessibilityLabel("磁盘排行排序")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(palette.secondary)
                TextField("搜索应用或进程", text: $search).textFieldStyle(.plain).font(.system(size: 11))
                    .accessibilityLabel("搜索磁盘读写进程")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
            }.padding(8).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
            ScrollView {
                if rows.isEmpty { emptyRecords(record) }
                else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.key) { index, row in
                            processRow(index, id: row.key, process: row.value, maxValue: max(1, rows.first.map { value($0.value.bytes) } ?? 1))
                        }
                    }
                }
            }.frame(height: compact ? 180 : nil).frame(minHeight: 0, maxHeight: .infinity)
        }.frame(minHeight: 0, maxHeight: .infinity).layoutPriority(-1)
    }
    private func processRow(_ index: Int, id: String, process: DiskProcessUsage, maxValue: UInt64) -> some View {
        let available = ProcessLocation.existingURL(process.path) != nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index+1)").font(.system(size: 10)).foregroundStyle(palette.secondary).frame(width: 12, height: 26)
                Group {
                    if let icon = monitor.icons[process.name] {
                        Image(nsImage: icon).resizable().scaledToFit()
                    } else {
                        Image(systemName: process.path.hasSuffix(".app") ? "app.dashed" : "terminal").font(.system(size: 18)).foregroundStyle(palette.secondary)
                    }
                }.frame(width: 26, height: 26)
                    .onAppear { monitor.loadDiskIcon(process.name, path: process.path) }
                VStack(spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(process.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 6)
                        Text(diskVolume(value(process.bytes))).font(.system(size: 12, weight: .semibold)).monospacedDigit().fixedSize()
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.track)
                            Capsule().fill(palette.accent).frame(width: geometry.size.width*CGFloat(Double(value(process.bytes))/Double(maxValue)))
                        }
                    }.frame(height: 3)
                    HStack(spacing: 4) {
                        Text("读 \(diskVolume(process.bytes.read))  写 \(diskVolume(process.bytes.written))").font(.system(size: 10)).monospacedDigit()
                        Spacer(minLength: 0)
                        Button {
                            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
                        } label: {
                            Image(systemName: expanded.contains(id) ? "chevron.up" : "chevron.down").font(.system(size: 9)).frame(width: 22, height: 16).contentShape(Rectangle())
                        }.buttonStyle(.plain).help(expanded.contains(id) ? "收起详情" : "展开路径与统计详情")
                            .accessibilityLabel("\(process.name)，\(expanded.contains(id) ? "收起" : "展开")详情")
                    }.foregroundStyle(palette.secondary)
                }
            }
            if expanded.contains(id) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(process.path).textSelection(.enabled)
                    Text(process.path.hasSuffix(".app") ? "应用与其辅助进程合并；覆盖所有磁盘。" : "系统进程计数；覆盖所有磁盘。")
                }.font(.system(size: 10)).foregroundStyle(palette.secondary).padding(.leading, 46)
            }
        }.padding(.vertical, 9).contentShape(Rectangle())
            .contextMenu {
                Button { ProcessLocation.reveal(process.path) } label: {
                    Label("打开位置", systemImage: "folder")
                }.disabled(!available)
            }
    }
    private func emptyRecords(_ record: DiskDay) -> some View {
        VStack(spacing: 8) {
            Image(systemName: search.isEmpty ? "internaldrive" : "magnifyingglass").font(.system(size: 22)).foregroundStyle(palette.secondary)
            Text(!search.isEmpty ? "没有匹配的进程" : monitor.paused ? "统计已暂停" : record.seconds > 0 ? "此时段未采集到进程读写" : "这个时段还没有读写记录")
                .font(.system(size: 12, weight: .medium))
            Text(search.isEmpty ? "从开启监控后累计，历史无法补算；缺失记录不表示实际读写为零。" : "换个名称搜索，或清除筛选。")
                .font(.system(size: 11)).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
            if !search.isEmpty { Button("清除搜索") { search = "" }.controlSize(.small) }
            else if monitor.paused { Button("继续记录") { monitor.togglePause() }.controlSize(.small) }
            else if !disk.samplingError.isEmpty { Button("重试采集") { disk.sample() }.controlSize(.small) }
        }.padding(18).frame(maxWidth: .infinity)
    }
    private var health: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if disk.healthLoading {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("正在读取磁盘信息…").font(.system(size: 11)) }.foregroundStyle(palette.secondary)
                }
                if !disk.healthError.isEmpty {
                    banner(disk.healthError)
                    Button("重新读取") { disk.refreshHealth(force: true) }.controlSize(.small)
                }
                if let device = disk.device {
                    HStack(spacing: 8) {
                        Image(systemName: device.internalDisk ? "internaldrive" : "externaldrive").font(.system(size: 23)).foregroundStyle(palette.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle).help(device.name)
                            Text("\(device.internalDisk ? "内置" : "外置") \(device.solidState ? "SSD" : "磁盘") · \(diskVolume(device.capacity))")
                                .font(.system(size: 10)).foregroundStyle(palette.secondary)
                        }
                        Spacer(minLength: 4)
                        PanelMenu(entries: disk.devices.map { item in
                            ("\(item.name) (\(item.id))", { disk.selectedDevice = item.id })
                        }) {
                            HStack(spacing: 6) {
                                Text(device.internalDisk ? "内置磁盘" : device.name).lineLimit(1).truncationMode(.middle)
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
                            }.font(.system(size: 11)).foregroundStyle(palette.text)
                                .padding(.horizontal, 8).padding(.vertical, 5).background(palette.track)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }.frame(maxWidth: 100).accessibilityLabel("选择物理磁盘")
                    }
                    healthHero(device)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            cell("温度", device.temperature.map { "\($0) °C" })
                            Rectangle().fill(palette.border).frame(width: 0.5)
                            cell("累计主机写入", device.hostWritten.map(diskVolume))
                        }.fixedSize(horizontal: false, vertical: true)
                        Rectangle().fill(palette.border).frame(height: 0.5)
                        HStack(spacing: 0) {
                            cell("通电时间", device.powerOnHours.map { "\($0.formatted()) 小时" })
                            Rectangle().fill(palette.border).frame(width: 0.5)
                            cell("介质与数据完整性错误", device.mediaErrors.map { $0.formatted() })
                        }.fixedSize(horizontal: false, vertical: true)
                    }.clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(palette.border, lineWidth: 0.5))
                    Text("磁盘详情").font(.system(size: 12, weight: .semibold)).padding(.top, 2)
                    fact("型号", device.model.isEmpty ? "未提供" : device.model)
                    fact("可用备用空间", device.availableSpare.map { "\($0)%" } ?? "未提供")
                    fact("累计主机读取", device.hostRead.map(diskVolume) ?? "未提供")
                    Text("硬件累计读写与流量喵记录期间的进程统计分开展示。缺少指标时显示“未提供”。")
                        .font(.system(size: 10)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                } else if !disk.healthLoading && disk.healthError.isEmpty {
                    VStack(spacing: 10) {
                        Text("没有找到物理磁盘").font(.system(size: 13, weight: .medium))
                        Button("重新检测") { disk.refreshHealth(force: true) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 36)
                }
            }.padding(.trailing, 2)
        }.frame(height: compact ? 300 : nil).frame(minHeight: 0, maxHeight: .infinity)
    }
    private func healthHero(_ device: DiskDevice) -> some View {
        let title: String
        switch device.status {
        case .normal: title = "磁盘运行正常"
        case .warning: title = "磁盘报告硬件警告"
        case .unavailable: title = "健康信息未提供"
        case .permission: title = "健康信息访问受限"
        case .failed: title = "暂时无法读取健康信息"
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                Label(device.status == .normal ? "SMART 正常" : device.status == .warning ? "需关注" : "未读取",
                      systemImage: device.status == .normal ? "checkmark.circle" : device.status == .warning ? "exclamationmark.triangle" : "minus.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(device.status == .normal ? palette.success : device.status == .warning ? palette.warning : palette.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(device.status == .normal ? palette.successSurface : device.status == .warning ? palette.warningSurface : palette.track)
                    .clipShape(Capsule()).fixedSize()
            }
            Text(device.message).font(.system(size: 11)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            if let used = device.enduranceUsed {
                HStack { Text("额定耐久度已用"); Spacer(); Text("\(used)%").fontWeight(.semibold).monospacedDigit() }.font(.system(size: 11)).padding(.top, 4)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.accent).frame(width: geometry.size.width*CGFloat(min(100,max(0,used)))/100)
                    }
                }.frame(height: 4)
                Text("磁盘提供的耐久度估算，不代表剩余寿命。")
                    .font(.system(size: 10)).foregroundStyle(palette.secondary)
            }
            if device.status == .failed { Button("重试") { disk.refreshHealth(force: true) }.controlSize(.small) }
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
            } else { Text("未提供").font(.system(size: 13, weight: .semibold)) }
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
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button { explanation.toggle() } label: { Label(disk.healthView ? "数据说明" : "统计口径", systemImage: "info.circle") }
                    .buttonStyle(.borderless)
                Spacer()
                if disk.healthView {
                    if let device = disk.device { Text(device.updated, style: .time).monospacedDigit().help("最近成功读取时间") }
                    Button("刷新") { disk.refreshHealth(force: true) }.buttonStyle(.borderless).disabled(disk.healthLoading)
                } else {
                    Button { disk.export() } label: { Label("导出 CSV", systemImage: "square.and.arrow.up") }.buttonStyle(.borderless)
                }
            }.font(.system(size: 10)).foregroundStyle(palette.secondary)
            if explanation {
                ScrollView {
                    Text("进程读写来自系统计数器增量，覆盖所有磁盘，应用辅助进程合并。它不等于 SSD 闪存物理写入，也不用于推算寿命。短暂进程、权限及共享 I/O 会影响归属；不强行归到应用。\n\n7 天、30 天包含今日，累计自开始记录起算。仅统计运行期间的采样，睡眠、暂停和漏采不补零。\n\n硬件健康信息按需读取，之后每 10 分钟刷新；不同硬盘和连接提供的字段不同，不安装第三方驱动或要求关闭系统保护。\n\n开始记录：\(disk.ledger.firstStarted.formatted(date: .numeric, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(height: 92).padding(8).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }
}
