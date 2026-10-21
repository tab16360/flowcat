import Foundation

@main struct DiskAlertTests {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ text: String) { precondition(value(), text); count += 1; print("PASS: " + text) }
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_792_598_400) // minute-aligned
        let path = "/Applications/Test.app"
        func usage(_ bytes: UInt64) -> [String: DiskProcessUsage] { [path: .init(name: "Test", path: path, bytes: .init(written: bytes))] }
        var prefs = DiskAlertPreferences(); prefs.enabled = true
        prefs.policy = DiskAlertPolicy(sustainedMBps: 1, hourlyGB: 0, dailyGB: 0)
        var engine = DiskAlertEngine(), memory = DiskAlertMemory(), found: [DiskWriteAlert] = []
        for i in 0..<60 {
            found += engine.ingest(from: start.addingTimeInterval(Double(i)*10), to: start.addingTimeInterval(Double(i+1)*10), processes: usage(20_000_000), daily: [:], preferences: prefs, memory: &memory)
        }
        check(found.count == 1 && found[0].kind == .sustained, "sustained alert requires ten complete observed minutes")
        for i in 60..<90 {
            found += engine.ingest(from: start.addingTimeInterval(Double(i)*10), to: start.addingTimeInterval(Double(i+1)*10), processes: usage(20_000_000), daily: [:], preferences: prefs, memory: &memory)
        }
        check(found.count == 1, "one continuous episode does not spam")
        var restarted = DiskAlertEngine()
        let restoredMemory = try JSONDecoder().decode(DiskAlertMemory.self, from: JSONEncoder().encode(memory))
        memory = restoredMemory
        var afterRestart: [DiskWriteAlert] = []
        for i in 90..<150 {
            afterRestart += restarted.ingest(from: start.addingTimeInterval(Double(i)*10), to: start.addingTimeInterval(Double(i+1)*10), processes: usage(20_000_000), daily: [:], preferences: prefs, memory: &memory)
        }
        check(afterRestart.isEmpty, "persisted cooldown prevents alerts after app restart")
        engine.clear(); memory = .init(); found = []
        for i in 0..<60 {
            if i == 30 { engine.resetContinuity(); continue }
            found += engine.ingest(from: start.addingTimeInterval(Double(i)*10), to: start.addingTimeInterval(Double(i+1)*10), processes: usage(20_000_000), daily: [:], preferences: prefs, memory: &memory)
        }
        check(found.isEmpty, "sleep or invalid sampling breaks sustained evidence")
        engine.clear(); memory = .init(); found = []
        for i in 0..<60 {
            found += engine.ingest(from: start.addingTimeInterval(Double(i)*10), to: start.addingTimeInterval(Double(i+1)*10), processes: i == 30 ? [:] : usage(20_000_000), daily: [:], preferences: prefs, memory: &memory)
        }
        check(found.isEmpty, "unavailable process counters never count as a healthy recovery")
        prefs.policy = .init(sustainedMBps: 0, hourlyGB: 0.5, dailyGB: 1)
        engine.clear(); memory = .init()
        let first = engine.ingest(from: start, to: start.addingTimeInterval(10), processes: usage(600_000_000), daily: usage(1_100_000_000), preferences: prefs, memory: &memory)
        check(first.count == 1 && first[0].kind == .hourly, "simultaneous rules emit one notification per application")
        check(engine.ingest(from: start.addingTimeInterval(10), to: start.addingTimeInterval(20), processes: usage(1), daily: usage(1_100_000_001), preferences: prefs, memory: &memory).isEmpty, "daily and hourly budgets deduplicate")
        let nextDay = start.addingTimeInterval(86400)
        let next = engine.ingest(from: nextDay, to: nextDay.addingTimeInterval(10), processes: usage(1), daily: usage(1_100_000_000), preferences: prefs, memory: &memory)
        check(next.count == 1 && next[0].kind == .daily, "daily budget rearms on a different local day")
        engine.clear(); memory = .init(); prefs.ignored.insert(path)
        check(engine.ingest(from: start, to: start.addingTimeInterval(10), processes: usage(600_000_000), daily: usage(2_000_000_000), preferences: prefs, memory: &memory).isEmpty && engine.series.isEmpty, "ignored applications do not allocate alert history")
        prefs.ignored = []; prefs.snoozedUntil[path] = start.addingTimeInterval(60)
        check(engine.ingest(from: start, to: start.addingTimeInterval(10), processes: usage(600_000_000), daily: usage(2_000_000_000), preferences: prefs, memory: &memory).isEmpty, "temporary snooze suppresses alerts")
        check(!engine.ingest(from: start.addingTimeInterval(60), to: start.addingTimeInterval(70), processes: usage(1), daily: usage(2_000_000_000), preferences: prefs, memory: &memory).isEmpty, "snooze expiry resumes budget checking")
        engine.clear(); memory = .init(); prefs.snoozedUntil = [:]; prefs.enabled = false
        check(engine.ingest(from: start, to: start.addingTimeInterval(10), processes: usage(600_000_000), daily: usage(2_000_000_000), preferences: prefs, memory: &memory).isEmpty && engine.series.isEmpty, "disabled alerts do not allocate minute buffers")
        prefs.enabled = true; prefs.policy = .init(sustainedMBps: 0, hourlyGB: 0, dailyGB: 0)
        var many: [String: DiskProcessUsage] = [:]
        for i in 0..<800 { let p = "/app/\(i)"; many[p] = .init(name: "same name", path: p, bytes: .init(written: UInt64(i+1))) }
        _ = engine.ingest(from: start, to: start.addingTimeInterval(10), processes: many, daily: [:], preferences: prefs, memory: &memory)
        check(engine.series.count == 512, "minute buffer has a fixed application cap and separates same-name paths")
        _ = engine.ingest(from: start.addingTimeInterval(3700), to: start.addingTimeInterval(3710), processes: [:], daily: [:], preferences: prefs, memory: &memory)
        check(engine.series.isEmpty, "inactive minute buffers expire after one hour")
        prefs.policy = .init(sustainedMBps: 0, hourlyGB: 0.5, dailyGB: 0)
        engine.clear(); memory = .init()
        _ = engine.ingest(from: start, to: start.addingTimeInterval(10), processes: usage(600_000_000), daily: [:], preferences: prefs, memory: &memory)
        for i in 1...430 {
            _ = engine.ingest(from: start.addingTimeInterval(Double(i)*10), to: start.addingTimeInterval(Double(i+1)*10), processes: usage(0), daily: [:], preferences: prefs, memory: &memory)
        }
        check(!engine.series[path, default: .init(name: "", lastSeen: start)].active.contains(.hourly), "budget episode rearms after five minutes below threshold")
        let again = engine.ingest(from: start.addingTimeInterval(4310), to: start.addingTimeInterval(4320), processes: usage(600_000_000), daily: [:], preferences: prefs, memory: &memory)
        check(again.count == 1, "recovered episode may alert again after cooldown")
        print("All \(count) disk alert checks passed.")
    }
}
