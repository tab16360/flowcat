import AppKit
import Darwin
import Foundation

// Reads per-process counters directly; no shell, privileged helper or third-party runtime.
enum DiskSampler {
    static func capture() -> DiskSnapshot {
        let required = proc_listallpids(nil, 0)
        guard required > 0 else { return DiskSnapshot(date: Date(), counters: [:], valid: false) }
        var pids = [pid_t](repeating: 0, count: Int(required)+256)
        var count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        if count >= pids.count {
            pids = [pid_t](repeating: 0, count: Int(count)+1024)
            count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        }
        guard count > 0, count < pids.count else { return DiskSnapshot(date: Date(), counters: [:], valid: false) }
        var counters: [String: DiskProcessCounter] = [:], denied = 0
        for pid in pids.prefix(Int(count)) where pid > 0 {
            var info = rusage_info_v2()
            let rc = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
            }
            guard rc == 0 else { if errno == EPERM || errno == EACCES { denied += 1 }; continue }
            var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
            let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
            var path = length > 0 ? String(cString: buffer) : ""
            if path.isEmpty {
                buffer = [CChar](repeating: 0, count: 256)
                let n = buffer.withUnsafeMutableBytes { proc_name(pid, $0.baseAddress, UInt32($0.count)) }
                guard n > 0 else { continue }; path = String(cString: buffer)
            }
            var group = path, name = URL(fileURLWithPath: path).lastPathComponent
            if let suffix = path.range(of: ".app/") {
                group = String(path[..<suffix.lowerBound])+".app"
                name = URL(fileURLWithPath: group).deletingPathExtension().lastPathComponent
            }
            let key = "\(pid):\(info.ri_proc_start_abstime)"
            counters[key] = DiskProcessCounter(identity: key, group: group, usage: DiskProcessUsage(name: name, path: group,
                bytes: DiskBytes(read: info.ri_diskio_bytesread, written: info.ri_diskio_byteswritten)))
        }
        return DiskSnapshot(date: Date(), counters: counters, denied: denied, valid: !counters.isEmpty)
    }
}

enum DiskHardware {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    // diskutil only runs on health refresh, never on each I/O sample.
    private static func plist(_ arguments: [String]) throws -> [String: Any] {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = arguments; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        var data = Data()
        let group = DispatchGroup(); group.enter()
        do { try process.run() } catch { group.leave(); throw error }
        DispatchQueue.global(qos: .utility).async { data = pipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        let limit = Date().addingTimeInterval(8)
        while process.isRunning && Date() < limit { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit(); group.wait()
        guard process.terminationStatus == 0,
              let result = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw Failure(message: tr("Could not read disk information. Check the connection and try again.", "无法读取磁盘信息，请检查连接后重试。"))
        }
        return result
    }
    static func read() throws -> [DiskDevice] {
        let listing = try plist(["list", "-plist", "physical"])
        guard let disks = listing["WholeDisks"] as? [String] else { throw Failure(message: tr("Could not list physical disks.", "未能列出物理磁盘。")) }
        var volumeNames: [String: Set<String>] = [:]
        if let apfs = try? plist(["apfs", "list", "-plist"]), let containers = apfs["Containers"] as? [[String: Any]] {
            for container in containers {
                let stores = (container["PhysicalStores"] as? [[String: Any]] ?? []).compactMap { $0["DeviceIdentifier"] as? String }
                let names = (container["Volumes"] as? [[String: Any]] ?? []).compactMap { volume -> String? in
                    let roles = Set(volume["Roles"] as? [String] ?? [])
                    guard roles.isDisjoint(with: ["Data", "Preboot", "Recovery", "VM", "Update", "xART", "Hardware"]),
                          let name = volume["Name"] as? String, !name.isEmpty else { return nil }
                    return name
                }
                for store in stores {
                    if let id = disks.first(where: { store == $0 || store.hasPrefix($0+"s") }) { volumeNames[id, default: []].formUnion(names) }
                }
            }
        }
        return disks.filter { $0.range(of: "^disk[0-9]+$", options: .regularExpression) != nil }.map { id in
            do {
                var disk = DiskDevice.fromPlist(try plist(["info", "-plist", id]), id: id)
                if disk.hostWritten == nil || disk.temperature == nil {
                    var value = FCNVMeHealth()
                    let result = id.withCString { fc_read_nvme($0, &value) }
                    if result == 0 {
                        disk.status = value.warning == 0 ? .normal : .warning
                        disk.message = value.warning == 0 ? tr("The drive reports no hardware warnings.", "磁盘自身报告未检测到硬件警告。") : tr("The drive reports a hardware warning. Back up important data soon.", "磁盘报告硬件警告，建议尽快备份重要数据。")
                        disk.temperature = value.temperature > -273 ? Int(value.temperature) : nil
                        disk.enduranceUsed = Int(value.used); disk.availableSpare = Int(value.spare)
                        func units(_ value: UInt64, _ valid: UInt8) -> UInt64? {
                            let (n,overflow) = value.multipliedReportingOverflow(by: 512_000); return valid != 0 && !overflow ? n : nil
                        }
                        disk.hostRead = units(value.read_units, value.valid_read); disk.hostWritten = units(value.written_units, value.valid_written)
                        disk.powerOnHours = value.valid_hours != 0 ? value.hours : nil; disk.mediaErrors = value.valid_errors != 0 ? value.errors : nil
                    } else if result == 2 && disk.status == .unavailable {
                        disk.status = .permission; disk.message = tr("macOS denied access to hardware health. Process disk activity is still available.", "系统拒绝读取硬件健康信息。可继续查看进程读写统计。")
                    } else if result == 3 && disk.status == .unavailable {
                        disk.status = .failed; disk.message = tr("Could not read hardware health this time. Try again.", "本次未能读取硬件健康信息，请重试。")
                    }
                }
                if let names = volumeNames[id], !names.isEmpty { disk.name = names.sorted().joined(separator: " · ") }
                return disk
            } catch {
                return DiskDevice(id: id, name: id, model: "", internalDisk: false, capacity: 0, solidState: false,
                    status: .failed, message: error.localizedDescription)
            }
        }.sorted { a,b in a.internalDisk == b.internalDisk ? a.id < b.id : a.internalDisk }
    }
}

final class DiskMonitor: ObservableObject {
    @Published var ledger: DiskLedger
    @Published var period: DiskPeriod = .today
    @Published var selectedDate = Date()
    @Published var healthView = false
    @Published var readRate: Double = 0
    @Published var writeRate: Double = 0
    @Published var denied = 0
    @Published var sampledProcesses = 0
    @Published var lastSample: Date?
    @Published var samplingError = ""
    @Published var storageError = ""
    @Published var devices: [DiskDevice] = []
    @Published var selectedDevice = ""
    @Published var healthLoading = false
    @Published var healthError = ""
    @Published var showMenuBarDiskSpeed = UserDefaults.standard.bool(forKey: "showMenuBarDiskSpeed") {
        didSet { UserDefaults.standard.set(showMenuBarDiskSpeed, forKey: "showMenuBarDiskSpeed"); onUpdate?() }
    }
    var isPreview = false
    var onUpdate: (() -> Void)?
    let file: URL
    let alerts: DiskAlertController
    private var dirty = false
    private let queue = DispatchQueue(label: "local.flowcat.disk-sampling", qos: .utility)
    private let healthQueue = DispatchQueue(label: "local.flowcat.disk-health", qos: .utility)
    private var accumulator = DiskAccumulator()
    private var inFlight = false, paused = false, writable = true
    private var generation = 0
    private var previousTime: Date?
    private var lastSaved = Date.distantPast, lastHealth = Date.distantPast
    init(file: URL) {
        self.file = file
        self.alerts = DiskAlertController(file: file.deletingLastPathComponent().appendingPathComponent("disk-alerts.json"))
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let value = try JSONDecoder().decode(DiskLedger.self, from: Data(contentsOf: file))
                guard value.version == 1 else { throw DiskHardware.Failure(message: tr("Unsupported disk history version", "磁盘历史版本不受支持")) }
                ledger = value
            } catch {
                ledger = DiskLedger(); writable = false
                storageError = tr("Disk history could not be read. The original file was kept and writing has stopped.", "磁盘历史无法读取，已保留原文件并停止写入。")
            }
        } else { ledger = DiskLedger() }
    }
    var keys: [String] { period.keys(now: Date(), date: selectedDate, available: Array(ledger.days.keys)) }
    var selected: DiskDay { ledger.sum(keys) }
    var device: DiskDevice? { devices.first { $0.id == selectedDevice } ?? devices.first }
    var historyStart: Date { min(Date(), ledger.firstStarted) }
    func reset() { alerts.resetContinuity(); generation += 1; accumulator.reset(); previousTime = nil; readRate = 0; writeRate = 0; onUpdate?() }
    func setPaused(_ value: Bool) { paused = value; reset() }
    func sample() {
        guard !isPreview, !paused, !inFlight else { return }
        inFlight = true; let epoch = generation
        queue.async { [weak self] in
            let snapshot = autoreleasepool { DiskSampler.capture() }
            DispatchQueue.main.async {
                guard let self else { return }; self.inFlight = false
                guard epoch == self.generation, !self.paused else { return }
                let old = self.previousTime
                let change = self.accumulator.apply(snapshot, ledger: &self.ledger)
                self.previousTime = snapshot.valid ? snapshot.date : nil
                if let old, change != nil {
                    self.dirty = true
                    self.alerts.ingest(from: old, to: snapshot.date, processes: self.accumulator.lastChanges,
                                      daily: self.ledger.days[DateKeys.day(snapshot.date)]?.processes ?? [:])
                } else { self.alerts.resetContinuity() }
                self.readRate = 0; self.writeRate = 0
                if let change, let old {
                    let interval = snapshot.date.timeIntervalSince(old)
                    if interval > 0 { self.readRate = Double(change.read)/interval; self.writeRate = Double(change.written)/interval }
                }
                self.denied = snapshot.denied; self.sampledProcesses = snapshot.counters.count
                self.samplingError = snapshot.valid ? "" : tr("Disk activity is temporarily unavailable. Try again.", "暂时无法采集磁盘读写，请重试。")
                if snapshot.valid { self.lastSample = snapshot.date }
                if snapshot.date.timeIntervalSince(self.lastSaved) >= 60 { self.save() }
                self.onUpdate?()
            }
        }
        if !devices.isEmpty, Date().timeIntervalSince(lastHealth) >= 600 { refreshHealth() }
    }
    func refreshHealth(force: Bool = false) {
        guard !isPreview, !healthLoading, force || devices.isEmpty || Date().timeIntervalSince(lastHealth) >= 600 else { return }
        healthLoading = true; healthError = ""
        healthQueue.async { [weak self] in
            let result = Result { try autoreleasepool { try DiskHardware.read() } }
            DispatchQueue.main.async {
                guard let self else { return }; self.healthLoading = false; self.lastHealth = Date()
                switch result {
                case .success(let devices):
                    self.devices = devices
                    if !devices.contains(where: { $0.id == self.selectedDevice }) { self.selectedDevice = devices.first?.id ?? "" }
                case .failure(let error): self.devices = []; self.selectedDevice = ""; self.healthError = error.localizedDescription
                }
            }
        }
    }
    func save() {
        guard writable, dirty else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(ledger).write(to: file, options: .atomic); storageError = ""; dirty = false; lastSaved = Date()
        } catch { storageError = tr("Could not save disk history: ", "磁盘统计保存失败：") + error.localizedDescription }
    }
    func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = tr("FlowCat-disk-", "流量喵-磁盘读写-") + "\(DateKeys.day(Date())).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func field(_ text: String) -> String {
            let guarded = ["=","+","-","@","\t","\r","\n"].contains(String(text.prefix(1))) ? "'"+text : text
            return "\""+guarded.replacingOccurrences(of: "\"", with: "\"\"")+"\""
        }
        var csv = tr("Date,Process or app,Path,Bytes read,Bytes written,Covered seconds\n", "日期,进程或应用,路径,读取字节,写入字节,覆盖秒数\n")
        for key in keys.sorted() { if let day = ledger.days[key] {
            csv += "\(key),\(tr("All sampled processes", "已采集进程合计")),,\(day.bytes.read),\(day.bytes.written),\(Int(day.seconds))\n"
            for value in day.processes.values.sorted(by: { $0.path < $1.path }) {
                csv += "\(key),\(field(value.name)),\(field(value.path)),\(value.bytes.read),\(value.bytes.written),\n"
            }
        } }
        do { try ("\u{FEFF}"+csv).write(to: url, atomically: true, encoding: .utf8) }
        catch { storageError = tr("Could not export disk history: ", "磁盘统计导出失败：") + error.localizedDescription }
    }
}
