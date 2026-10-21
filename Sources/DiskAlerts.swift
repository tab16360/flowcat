import Foundation

struct DiskAlertPolicy: Codable, Equatable {
    var sustainedMBps: Double = 1
    var hourlyGB: Double = 2
    var dailyGB: Double = 10
}
struct DiskAlertPreferences: Codable {
    var enabled = false
    var policy = DiskAlertPolicy()
    var overrides: [String: DiskAlertPolicy] = [:]
    var ignored: Set<String> = []
    var snoozedUntil: [String: Date] = [:]
}
enum DiskAlertKind: String, Codable { case sustained, hourly, daily
    var title: String { switch self { case .sustained: return "持续高写入"; case .hourly: return "小时写入预算"; case .daily: return "每日写入预算" } }
}
struct DiskWriteAlert: Codable, Identifiable {
    var id = UUID().uuidString
    var date: Date
    var path: String
    var name: String
    var kind: DiskAlertKind
    var bytes: UInt64
    var seconds: Double
}
struct DiskAlertMemory: Codable {
    var recent: [DiskWriteAlert] = []
    // Persists deduplication across launches. No raw samples are written.
    var lastNotified: [String: Date] = [:]
}
struct DiskAlertMinute {
    var minute: Int = -1
    var bytes: UInt64 = 0
    var seconds: Double = 0
    var highSeconds: Double = 0
}
struct DiskAlertSeries {
    var name: String
    var lastSeen: Date
    var continuousSince: Date?
    var slots = [DiskAlertMinute](repeating: DiskAlertMinute(), count: 61)
    var active: Set<DiskAlertKind> = []
    var recoveredSince: [DiskAlertKind: Date] = [:]
}
struct DiskAlertEngine {
    private(set) var series: [String: DiskAlertSeries] = [:]
    private var lastEnd: Date?
    // Roughly 1 MB of bucket payload at the cap; inactive entries expire after an hour.
    static let capacity = 512
    mutating func resetContinuity() {
        lastEnd = nil
        for key in Array(series.keys) {
            for i in series[key]!.slots.indices { series[key]!.slots[i].highSeconds = 0 }
            series[key]!.recoveredSince.removeAll()
            series[key]!.continuousSince = nil
        }
    }
    mutating func clear() { series.removeAll(); lastEnd = nil }
    mutating func ingest(from start: Date, to end: Date, processes: [String: DiskProcessUsage],
                         daily: [String: DiskProcessUsage], preferences: DiskAlertPreferences,
                         memory: inout DiskAlertMemory) -> [DiskWriteAlert] {
        let duration = end.timeIntervalSince(start)
        guard preferences.enabled, duration > 0, duration < 45 else { resetContinuity(); return [] }
        if let lastEnd, abs(start.timeIntervalSince(lastEnd)) > 1 { resetContinuity() }
        lastEnd = end
        series = series.filter { end.timeIntervalSince($0.value.lastSeen) < 3600 }
        memory.lastNotified = memory.lastNotified.filter { end.timeIntervalSince($0.value) < 172800 }
        for (path, process) in processes.sorted(by: { $0.value.bytes.written > $1.value.bytes.written }) where process.bytes.written > 0 {
            guard !preferences.ignored.contains(path) else { series.removeValue(forKey: path); continue }
            if series[path] == nil {
                guard series.count < Self.capacity else { continue }
                series[path] = DiskAlertSeries(name: process.name, lastSeen: end)
            }
        }
        let minute = Int(floor(end.timeIntervalSince1970 / 60))
        var alerts: [DiskWriteAlert] = []
        for path in Array(series.keys).sorted() {
            guard !preferences.ignored.contains(path), var item = series[path] else { series.removeValue(forKey: path); continue }
            let policy = preferences.overrides[path] ?? preferences.policy
            let written = processes[path]?.bytes.written ?? 0
            if written > 0 { item.lastSeen = end; item.name = processes[path]?.name ?? item.name }
            guard processes[path] != nil else {
                for i in item.slots.indices { item.slots[i].highSeconds = 0 }
                item.recoveredSince.removeAll(); item.continuousSince = nil; series[path] = item; continue
            }
            if item.continuousSince == nil { item.continuousSince = start }
            var cursor = start, remaining = written
            while cursor < end {
                let m = Int(floor(cursor.timeIntervalSince1970 / 60))
                let next = min(end, Date(timeIntervalSince1970: Double(m + 1) * 60))
                let seconds = next.timeIntervalSince(cursor), slot = ((m % 61) + 61) % 61
                if item.slots[slot].minute != m { item.slots[slot] = DiskAlertMinute(minute: m) }
                let part = next == end ? remaining : min(remaining, UInt64(Double(written) * seconds / duration))
                remaining -= part
                item.slots[slot].bytes = DiskBytes.plus(item.slots[slot].bytes, part)
                item.slots[slot].seconds += seconds
                if policy.sustainedMBps > 0 && Double(written) / duration >= policy.sustainedMBps * 1e6 { item.slots[slot].highSeconds += seconds }
                cursor = next
            }
            let ten = item.slots.filter { $0.minute >= minute - 10 && $0.minute < minute }
            let hour = item.slots.filter { $0.minute > minute - 60 && $0.minute <= minute }
            let tenBytes = ten.reduce(UInt64(0)) { DiskBytes.plus($0, $1.bytes) }
            let tenSeconds = ten.reduce(0) { $0 + $1.seconds }
            let high = ten.reduce(0) { $0 + $1.highSeconds }
            let hourBytes = hour.reduce(UInt64(0)) { DiskBytes.plus($0, $1.bytes) }
            let dayBytes = daily[path]?.bytes.written ?? 0
            let candidates: [(DiskAlertKind, Bool, UInt64, Double)] = [
                (.sustained, policy.sustainedMBps > 0 && end.timeIntervalSince(item.continuousSince ?? end) >= 600 && tenSeconds >= 570 && high >= 480, tenBytes, tenSeconds),
                (.hourly, policy.hourlyGB > 0 && Double(hourBytes) >= policy.hourlyGB * 1e9, hourBytes, hour.reduce(0) { $0 + $1.seconds }),
                (.daily, written > 0 && policy.dailyGB > 0 && Double(dayBytes) >= policy.dailyGB * 1e9, dayBytes, 0)
            ]
            var pending: [DiskWriteAlert] = []
            for (kind, reached, bytes, seconds) in candidates {
                let day = kind == .daily ? ":" + DateKeys.day(end) : ""
                let key = path + ":" + kind.rawValue + day
                if reached {
                    item.recoveredSince.removeValue(forKey: kind)
                    let cooldown: TimeInterval = kind == .daily ? 172800 : 3600
                    let deduped = memory.lastNotified[key].map { end.timeIntervalSince($0) < cooldown } ?? false
                    if (kind == .daily || !item.active.contains(kind)), !deduped, (preferences.snoozedUntil[path] ?? .distantPast) <= end {
                        pending.append(DiskWriteAlert(date: end, path: path, name: item.name, kind: kind, bytes: bytes, seconds: seconds))
                        memory.lastNotified[key] = end
                        item.active.insert(kind)
                    }
                } else if kind != .daily {
                    if item.recoveredSince[kind] == nil { item.recoveredSince[kind] = end }
                    if end.timeIntervalSince(item.recoveredSince[kind]!) >= 300 { item.active.remove(kind) }
                }
            }
            // One notification per application per sample even if several rules cross together.
            if let alert = pending.first { alerts.append(alert) }
            series[path] = item
        }
        memory.recent.insert(contentsOf: alerts, at: 0)
        memory.recent = Array(memory.recent.prefix(40))
        return alerts
    }
    func minutes(for path: String, now: Date) -> [DiskAlertMinute] {
        guard let item = series[path] else { return [] }
        let m = Int(floor(now.timeIntervalSince1970 / 60))
        return item.slots.filter { $0.minute > m - 60 && $0.minute <= m }.sorted { $0.minute < $1.minute }
    }
}
