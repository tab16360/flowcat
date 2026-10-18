import Foundation

struct DiskBytes: Codable, Equatable {
    var read: UInt64 = 0
    var written: UInt64 = 0
    var total: UInt64 { Self.plus(read, written) }
    static func plus(_ a: UInt64, _ b: UInt64) -> UInt64 { let (v, overflow) = a.addingReportingOverflow(b); return overflow ? .max : v }
    mutating func add(_ b: DiskBytes) { read = Self.plus(read, b.read); written = Self.plus(written, b.written) }
    func delta(_ old: DiskBytes) -> DiskBytes { .init(read: read >= old.read ? read-old.read : 0, written: written >= old.written ? written-old.written : 0) }
}
struct DiskProcessUsage: Codable, Equatable {
    var name: String
    var path: String
    var bytes = DiskBytes()
}
struct DiskProcessCounter {
    var identity: String // PID + kernel process start time; PID reuse must not reuse a baseline.
    var group: String
    var usage: DiskProcessUsage
}
struct DiskSnapshot {
    var date: Date
    var counters: [String: DiskProcessCounter]
    var denied: Int = 0
    var valid = true
}
struct DiskBucket: Codable {
    var bytes = DiskBytes()
    var seconds: Double = 0
}
struct DiskDay: Codable {
    var processes: [String: DiskProcessUsage] = [:]
    var hours: [String: DiskBucket] = [:]
    var seconds: Double = 0
    var bytes: DiskBytes { processes.values.reduce(into: DiskBytes()) { $0.add($1.bytes) } }
}
enum DiskPeriod: String, CaseIterable {
    case today, seven, thirty, all, date
    var title: String { switch self { case .today: return "今日"; case .seven: return "近 7 天"; case .thirty: return "近 30 天"; case .all: return "累计"; case .date: return "所选日期" } }
    var short: String { switch self { case .seven: return "7 天"; case .thirty: return "30 天"; default: return title } }
    func keys(now: Date, date: Date, available: [String], calendar: Calendar = .current) -> [String] {
        switch self {
        case .all: return available.filter { $0 <= DateKeys.day(now, calendar: calendar) }.sorted()
        case .date: return [DateKeys.day(date, calendar: calendar)]
        default:
            let count = self == .seven ? 7 : self == .thirty ? 30 : 1
            return (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }.map { DateKeys.day($0, calendar: calendar) }
        }
    }
}
struct DiskLedger: Codable {
    var version = 1
    var firstStarted: Date = Date()
    var days: [String: DiskDay] = [:]
    func sum(_ keys: [String]) -> DiskDay {
        var result = DiskDay()
        for key in keys { if let day = days[key] {
            result.seconds += day.seconds
            for (id, value) in day.processes {
                var item = result.processes[id] ?? DiskProcessUsage(name: value.name, path: value.path)
                item.bytes.add(value.bytes); result.processes[id] = item
            }
        } }
        return result
    }
    // Split short samples at local hour/day boundaries. Distribute integer remainders to the last bucket.
    mutating func add(from start: Date, to end: Date, processes: [String: DiskProcessUsage], calendar: Calendar = .current) {
        let duration = end.timeIntervalSince(start)
        guard duration > 0, duration < 45 else { return }
        var cursor = start, remaining = processes.mapValues(\.bytes)
        while cursor < end {
            guard let boundary = calendar.dateInterval(of: .hour, for: cursor)?.end, boundary > cursor else { return }
            let next = min(end, boundary), seconds = next.timeIntervalSince(cursor)
            let dayKey = DateKeys.day(cursor, calendar: calendar)
            // An absolute hour key keeps the two repeated local hours at the DST fall-back separate.
            let hourKey = String(Int((calendar.dateInterval(of: .hour, for: cursor)?.start ?? cursor).timeIntervalSince1970))
            var day = days[dayKey] ?? DiskDay(), bucket = day.hours[hourKey] ?? DiskBucket()
            day.seconds += seconds; bucket.seconds += seconds
            for (id, process) in processes {
                let rest = remaining[id] ?? DiskBytes()
                func fraction(_ original: UInt64, _ remaining: UInt64) -> UInt64 {
                    if next == end { return remaining }
                    let value = Double(original) * seconds / duration
                    return value >= Double(remaining) ? remaining : UInt64(max(0, value))
                }
                let part = DiskBytes(read: fraction(process.bytes.read, rest.read), written: fraction(process.bytes.written, rest.written))
                remaining[id] = DiskBytes(read: rest.read-part.read, written: rest.written-part.written)
                guard part.total > 0 else { continue }
                var item = day.processes[id] ?? DiskProcessUsage(name: process.name, path: process.path)
                item.bytes.add(part); day.processes[id] = item; bucket.bytes.add(part)
            }
            day.hours[hourKey] = bucket; days[dayKey] = day; cursor = next
        }
    }
}
struct DiskAccumulator {
    private var previous: DiskSnapshot?
    mutating func reset() { previous = nil }
    mutating func apply(_ sample: DiskSnapshot, ledger: inout DiskLedger) -> DiskBytes? {
        guard sample.valid else { reset(); return nil }
        defer { previous = sample }
        guard let old = previous else { return nil }
        let seconds = sample.date.timeIntervalSince(old.date)
        guard seconds > 0, seconds < 45 else { return nil }
        var changes: [String: DiskProcessUsage] = [:], total = DiskBytes()
        for (key, counter) in sample.counters {
            guard let before = old.counters[key], before.group == counter.group else { continue }
            let delta = counter.usage.bytes.delta(before.usage.bytes)
            guard delta.total > 0 else { continue }
            var item = changes[counter.group] ?? DiskProcessUsage(name: counter.usage.name, path: counter.usage.path)
            item.bytes.add(delta); changes[counter.group] = item; total.add(delta)
        }
        ledger.add(from: old.date, to: sample.date, processes: changes)
        return total
    }
}
enum DiskHealthStatus: String, Codable { case normal, warning, unavailable, permission, failed }
struct DiskDevice: Codable, Identifiable {
    var id: String
    var name: String
    var model: String
    var internalDisk: Bool
    var capacity: UInt64
    var solidState: Bool
    var status: DiskHealthStatus = .unavailable
    var message = "此连接未提供 SMART 健康信息。"
    var temperature: Int?
    var enduranceUsed: Int?
    var availableSpare: Int?
    var hostRead: UInt64?
    var hostWritten: UInt64?
    var powerOnHours: UInt64?
    var mediaErrors: UInt64?
    var updated: Date = Date()
    static func fromPlist(_ info: [String: Any], id: String) -> DiskDevice {
        func string(_ key: String) -> String { info[key] as? String ?? "" }
        var disk = DiskDevice(id: id, name: string("MediaName"), model: string("MediaName"),
            internalDisk: info["Internal"] as? Bool ?? false, capacity: (info["TotalSize"] as? NSNumber)?.uint64Value ?? 0,
            solidState: info["SolidState"] as? Bool ?? false)
        if disk.name.isEmpty { disk.name = id }
        switch string("SMARTStatus").lowercased() {
        case "verified": disk.status = .normal; disk.message = "磁盘自身报告未检测到硬件警告。"
        case "failing", "failed": disk.status = .warning; disk.message = "建议尽快备份重要数据，并检查磁盘。"
        default: break
        }
        // Newer macOS exposes these optional NVMe fields. Older systems use the native IOKit fallback.
        if let values = info["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any] {
            func u(_ key: String) -> UInt64? { (values[key] as? NSNumber)?.uint64Value }
            func low(_ key: String) -> UInt64? { guard (u(key+"_1") ?? 0) == 0 else { return nil }; return u(key+"_0") }
            func units(_ key: String) -> UInt64? { guard let v = low(key) else { return nil }; let (n,o) = v.multipliedReportingOverflow(by: 512_000); return o ? nil : n }
            if let t = u("TEMPERATURE"), t > 0 { disk.temperature = Int(t)-273 }
            disk.enduranceUsed = u("PERCENTAGE_USED").map(Int.init)
            disk.availableSpare = u("AVAILABLE_SPARE").map(Int.init)
            disk.hostRead = units("DATA_UNITS_READ"); disk.hostWritten = units("DATA_UNITS_WRITTEN")
            disk.powerOnHours = low("POWER_ON_HOURS"); disk.mediaErrors = low("MEDIA_ERRORS")
        }
        return disk
    }
}
func diskVolume(_ bytes: UInt64) -> String { bytes >= 1_000_000_000_000 ? String(format: "%.2f TB", Double(bytes)/1e12) : volume(bytes) }
