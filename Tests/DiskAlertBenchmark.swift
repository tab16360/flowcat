import Darwin
import Foundation

@main struct DiskAlertBenchmark {
    static func metrics() -> (Double, UInt64, UInt64) {
        var r = rusage(); getrusage(RUSAGE_SELF, &r)
        let cpu = Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec)/1e6
        var info = rusage_info_v2()
        _ = withUnsafeMutablePointer(to: &info) { p in p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0) } }
        return (cpu, info.ri_resident_size, info.ri_diskio_byteswritten)
    }
    static func main() throws {
        let enabled = CommandLine.arguments.contains("--enabled"), stress = CommandLine.arguments.contains("--stress")
        var prefs = DiskAlertPreferences(); prefs.enabled = enabled
        prefs.policy = .init(sustainedMBps: 10000, hourlyGB: 100000, dailyGB: 100000)
        var engine = DiskAlertEngine(), memory = DiskAlertMemory(), ledger = DiskLedger(), accumulator = DiskAccumulator()
        var durations: [Double] = [], old: Date?
        let baseline = metrics(), began = Date()
        if stress {
            let start = Date(timeIntervalSince1970: 1_792_598_400)
            var processes: [String: DiskProcessUsage] = [:]
            for i in 0..<512 { let path = "/Applications/Test\(i).app"; processes[path] = .init(name: "Test\(i)", path: path, bytes: .init(written: 2_000_000)) }
            for i in 0..<720 {
                let t = Date()
                _ = engine.ingest(from: start.addingTimeInterval(Double(i)*10), to: start.addingTimeInterval(Double(i+1)*10), processes: processes, daily: [:], preferences: prefs, memory: &memory)
                durations.append(Date().timeIntervalSince(t))
            }
        } else {
            for i in 0..<7 {
                if i > 0 { Thread.sleep(forTimeInterval: 10) }
                let snapshot = DiskSampler.capture()
                _ = accumulator.apply(snapshot, ledger: &ledger)
                if let old {
                    let t = Date()
                    _ = engine.ingest(from: old, to: snapshot.date, processes: accumulator.lastChanges, daily: [:], preferences: prefs, memory: &memory)
                    durations.append(Date().timeIntervalSince(t))
                }
                old = snapshot.date
            }
        }
        let end = metrics(), wall = Date().timeIntervalSince(began)
        let output: [String: Any] = ["enabled": enabled, "stress": stress, "wallSeconds": wall,
            "cpuSeconds": end.0-baseline.0, "averageCPUPercent": (end.0-baseline.0)/wall*100,
            "residentMB": Double(end.1)/1e6, "residentDeltaMB": Double(Int64(end.1)-Int64(baseline.1))/1e6,
            "diskWrittenBytes": end.2-baseline.2, "trackedApplications": engine.series.count,
            "meanRuleMilliseconds": durations.reduce(0,+)/Double(max(1,durations.count))*1000,
            "maxRuleMilliseconds": (durations.max() ?? 0)*1000]
        print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
