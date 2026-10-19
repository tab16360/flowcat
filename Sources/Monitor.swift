import AppKit
import Foundation
import ServiceManagement

struct CommandResult { var text: String; var error: String; var success: Bool }
func command(_ path: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    let output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = errors
    var environment = ProcessInfo.processInfo.environment
    environment["LC_ALL"] = "C"
    process.environment = environment
    do { try process.run() } catch { return CommandResult(text: "", error: error.localizedDescription, success: false) }
    // Drain both pipes concurrently to avoid blocking on machines with many sockets.
    let group = DispatchGroup()
    var stdout = Data(), stderr = Data()
    group.enter(); DispatchQueue.global().async { stdout = output.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    group.enter(); DispatchQueue.global().async { stderr = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
    let deadline = Date().addingTimeInterval(8)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    if process.isRunning { process.terminate() }
    process.waitUntilExit(); group.wait()
    return CommandResult(text: String(decoding: stdout, as: UTF8.self),
        error: String(decoding: stderr, as: UTF8.self), success: process.terminationStatus == 0)
}
final class TrafficMonitor: ObservableObject {
    let disk: DiskMonitor
    @Published var diskTab = false
    @Published var ledger: Ledger
    @Published var status = "正在开始采集…"
    @Published var download: Double = 0
    @Published var upload: Double = 0
    @Published var period = 0
    @Published var scope: TrafficScope = .all
    @Published var showMenuBarSpeed = UserDefaults.standard.object(forKey: "showMenuBarSpeed") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showMenuBarSpeed, forKey: "showMenuBarSpeed"); onUpdate?() }
    }
    @Published var selectedNetwork = "__all__"
    @Published var currentNetwork = NetworkContext(key: "__all__", name: "全部网络", identified: false)
    @Published var paused = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var lastSample: Date?
    @Published var icons: [String: NSImage] = [:]
    var onUpdate: (() -> Void)?
    private var timer: Timer?
    private var inFlight = false
    private var oldConnections: [String: ConnectionCounter] = [:]
    private var oldProcesses: [String: ProcessCounter] = [:]
    private var oldInterfaces: [String: Bytes] = [:]
    private var oldTime: Date?
    private var lastSaved = Date.distantPast
    private var oldNetwork: NetworkContext?
    private var appPaths: [String: String] = [:]
    private var iconOrder: [String] = []
    private let detector = NetworkDetector()
    private let queue = DispatchQueue(label: "local.trafficledger.sampling", qos: .utility)
    let file: URL
    private var brokenStore: URL?
    private var storeWritable = true
    init(file: URL? = nil) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("流量账本", isDirectory: true) // Keep the existing history directory across the rename.
        self.file = file ?? directory.appendingPathComponent("ledger.json")
        self.disk = DiskMonitor(file: self.file.deletingLastPathComponent().appendingPathComponent("disk-ledger.json"))
        if FileManager.default.fileExists(atPath: self.file.path) {
            do { self.ledger = try JSONDecoder().decode(Ledger.self, from: Data(contentsOf: self.file)) }
            catch {
                self.ledger = Ledger()
                brokenStore = self.file.deletingLastPathComponent().appendingPathComponent("ledger-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                if let backup = brokenStore {
                    do { try FileManager.default.moveItem(at: self.file, to: backup) }
                    catch { storeWritable = false }
                }
                status = "历史文件无法读取，原件未删除"
            }
        } else { self.ledger = Ledger() }
    }
    var selected: DayRecord {
        ledger.sum(keys: DateKeys.keys(period: period, now: Date(), available: Array(ledger.days.keys)),
                   networkName: selectedNetwork == "__all__" ? nil : selectedNetwork).scoped(scope)
    }
    var networkNames: [String] {
        guard currentNetwork.identified else { return [] }
        return Array(Set(ledger.networks.values.map(\.name) + [currentNetwork.name])).sorted()
    }
    var rows: [(String, Bytes)] { selected.processes.sorted { $0.value.total > $1.value.total } }
    func refreshLoginStatus() { loginEnabled = SMAppService.mainApp.status == .enabled }
    func setLogin(_ enabled: Bool) throws {
        defer { refreshLoginStatus() }
        if enabled { try SMAppService.mainApp.register() }
        else { try SMAppService.mainApp.unregister() }
    }
    func clearIcons() { icons.removeAll(); iconOrder.removeAll() }
    func loadDiskIcon(_ name: String, path: String) {
        if path.hasSuffix(".app") { appPaths[name] = path; loadIcon(name) }
    }
    func loadIcon(_ name: String) {
        guard icons[name] == nil, let path = appPaths[name] else { return }
        let thumbnail: NSImage? = autoreleasepool {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSWorkspace.shared.icon(forFile: path).draw(in: NSRect(x: 0, y: 0, width: 64, height: 64),
                from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            guard let image = bitmap.cgImage else { return nil }
            return NSImage(cgImage: image, size: NSSize(width: 32, height: 32))
        }
        guard let thumbnail else { return }
        if iconOrder.count >= 64 { icons.removeValue(forKey: iconOrder.removeFirst()) }
        iconOrder.append(name)
        icons[name] = thumbnail
    }
    func start() {
        detector.onAuthorizationChange = { [weak self] in self?.oldTime = nil; self?.sample() }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.sample() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.oldTime = nil; self?.disk.reset(); self?.sample()
        }
    }
    func togglePause() {
        paused.toggle(); oldTime = nil; disk.setPaused(paused)
        download = 0; upload = 0
        status = paused ? "已暂停统计" : "正在恢复采集…"
        if !paused { sample() }
        onUpdate?()
    }
    func sample() {
        disk.sample()
        guard !inFlight && !paused else { return }
        inFlight = true
        let context = detector.current()
        currentNetwork = context
        if !context.identified { selectedNetwork = "__all__" }
        let samplingNetwork = context
        queue.async { [weak self] in
          autoreleasepool {
            let proc = command("/usr/bin/nettop", ["-L", "1", "-n", "-J", "interface,bytes_in,bytes_out"])
            let net = command("/usr/sbin/netstat", ["-ibn"])
            let addresses = command("/sbin/ifconfig", [])
            let names = command("/bin/ps", ["-axo", "pid=,comm="])
            let now = Date()
            DispatchQueue.main.async { self?.apply(proc: proc, net: net, names: names.text, addresses: addresses.text, now: now, network: samplingNetwork) }
          }
        }
    }
    private func processNames(_ text: String) -> [String: (String, String)] {
        var result: [String: (String, String)] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard parts.count == 2 else { continue }
            let path = String(parts[1])
            if let end = path.range(of: ".app/") {
                let app = String(path[..<end.lowerBound]) + ".app"
                result[String(parts[0])] = (URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent, app)
            } else if path.contains("/claude/") || path.contains("/claude-code/") {
                result[String(parts[0])] = ("Claude Code", path)
            } else { result[String(parts[0])] = (URL(fileURLWithPath: path).lastPathComponent, path) }
        }
        return result
    }
    private func apply(proc: CommandResult, net: CommandResult, names: String, addresses: String, now: Date, network: NetworkContext) {
        inFlight = false
        guard !paused else { oldTime = nil; return }
        let processes = Parsers.processes(proc.text), interfaces = Parsers.interfaces(net.text)
        guard proc.success, !processes.isEmpty, net.success, !interfaces.isEmpty else {
            status = "采集不可用：请从 Finder 启动，勿在受限沙箱中运行"
            download = 0; upload = 0; oldTime = nil; onUpdate?(); return
        }
        let connections = ConnectionTraffic.parse(proc.text, localSubnets: LocalSubnet.parse(addresses))
        let mapping = processNames(names)
        for (_, item) in mapping where item.1.hasSuffix(".app") { appPaths[item.0] = item.1 }
        if let previous = oldTime {
            let interval = now.timeIntervalSince(previous)
            // Do not attribute sleep, pause or missed samples as observed history.
            if interval > 0 && interval < 45 && oldNetwork == network && currentNetwork == network {
                var physical = Bytes(), deltas: [String: Bytes] = [:]
                var activeInterfaces: [String] = []
                for (name, value) in interfaces {
                    if let old = oldInterfaces[name] {
                        let difference = value.difference(from: old)
                        physical.add(difference)
                        if difference.total > 0 { activeInterfaces.append(name) }
                    }
                }
                for (key, value) in processes {
                    guard let old = oldProcesses[key], old.name == value.name else { continue }
                    let pid = key.split(separator: ".").last.map(String.init) ?? ""
                    let item = mapping[pid]
                    let name = item?.0 ?? value.name
                    let delta = value.bytes.difference(from: old.bytes)
                    guard delta.total > 0 else { continue }
                    var sum = deltas[name] ?? Bytes(); sum.add(delta); deltas[name] = sum
                }
                let bucket = activeInterfaces.count > 1
                    ? NetworkContext(key: "__all__", name: "全部网络", identified: false) : network
                let breakdown = ConnectionTraffic.delta(current: connections, previous: oldConnections,
                    seconds: interval, names: mapping.mapValues { $0.0 })
                ledger.add(day: DateKeys.day(now), physical: physical, processes: deltas, seconds: interval, network: bucket, breakdown: breakdown)
                download = Double(physical.received) / interval
                upload = Double(physical.sent) / interval
                if now.timeIntervalSince(lastSaved) >= 60 { save(); lastSaved = now }
            } else { download = 0; upload = 0 }
        }
        oldConnections = connections
        oldProcesses = processes; oldInterfaces = interfaces; oldTime = now; oldNetwork = network; lastSample = now
        status = brokenStore == nil ? "采集中 · 每 10 秒更新" : "采集中 · 旧历史损坏文件已保留"
        onUpdate?()
    }
    func save() {
        disk.save()
        guard storeWritable else { status = "旧历史无法读取且备份失败，已停止写入以保留原件"; return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(ledger).write(to: file, options: .atomic)
        } catch { status = "统计保存失败：\(error.localizedDescription)" }
    }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "流量喵-\(DateKeys.day(Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var content = "日期,网络,分类,下载字节,上传字节,监控秒数\n"
        for key in ledger.days.keys.sorted() {
            let d = ledger.days[key]!
            content += "\(key),全部网络,整机网卡,\(d.physical.received),\(d.physical.sent),\(Int(d.monitoredSeconds))\n"
            for (name, b) in d.processes.sorted(by: { $0.key < $1.key }) {
                let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
                // Prevent spreadsheet formula interpretation of executable names.
                let safe = ["=", "+", "-", "@"].contains(String(escaped.prefix(1))) ? "'" + escaped : escaped
                content += "\(key),全部网络,\"\(safe)\",\(b.received),\(b.sent),\n"
            }
        }
        func csvField(_ value: String) -> String {
            var escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            if ["=", "+", "-", "@"].contains(String(escaped.prefix(1))) { escaped = "'" + escaped }
            return "\"" + escaped + "\""
        }
        for history in ledger.networks.values.sorted(by: { $0.name < $1.name }) {
            for key in history.days.keys.sorted() {
                let d = history.days[key]!
                content += "\(key),\(csvField(history.name)),整机网卡,\(d.physical.received),\(d.physical.sent),\(Int(d.monitoredSeconds))\n"
                for (name, b) in d.processes.sorted(by: { $0.key < $1.key }) {
                    content += "\(key),\(csvField(history.name)),\(csvField(name)),\(b.received),\(b.sent),\n"
                }
            }
        }
        func scopeCSV(day: String, network: String, record: DayRecord) {
            guard let b = record.breakdown else { return }
            for (label, bytes, processes) in [("互联网（连接估算）", b.internet, b.internetProcesses), ("局域网（连接估算）", b.local, b.localProcesses)] {
                content += "\(day),\(csvField(network)),\(label),\(bytes.received),\(bytes.sent),\(Int(b.seconds))\n"
                for (name, bytes) in processes.sorted(by: { $0.key < $1.key }) {
                    content += "\(day),\(csvField(network)),\(csvField(label + " · " + name)),\(bytes.received),\(bytes.sent),\n"
                }
            }
        }
        for (day, record) in ledger.days.sorted(by: { $0.key < $1.key }) { scopeCSV(day: day, network: "全部网络", record: record) }
        for history in ledger.networks.values.sorted(by: { $0.name < $1.name }) {
            for (day, record) in history.days.sorted(by: { $0.key < $1.key }) { scopeCSV(day: day, network: history.name, record: record) }
        }
        do { try ("\u{FEFF}" + content).write(to: url, atomically: true, encoding: .utf8) }
        catch { status = "导出失败：\(error.localizedDescription)" }
    }
}
