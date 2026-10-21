import Foundation

@main struct DiskIntegration {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }; print("PASS: \(message)")
    }
    static func wait(_ condition: () -> Bool) {
        let limit = Date().addingTimeInterval(5)
        while !condition() && Date() < limit { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
    }
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("flowcat-disk-test-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("disk-ledger.json")
        let monitor = DiskMonitor(file: file)
        monitor.sample(); wait { monitor.lastSample != nil }
        check(monitor.lastSample != nil && monitor.sampledProcesses > 0, "real process sampler establishes a baseline asynchronously")
        check(monitor.ledger.days.isEmpty, "first real sample does not import lifetime counters")
        let firstTime = monitor.lastSample!
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        monitor.sample(); wait { (monitor.lastSample ?? .distantPast) > firstTime }
        check(monitor.ledger.sum(Array(monitor.ledger.days.keys)).seconds > 0, "second real sample records observed coverage")
        monitor.save()
        let savedDate = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
        monitor.save()
        let duplicateDate = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as! Date
        check(duplicateDate == savedDate, "duplicate save without new sample never rewrites disk history")
        let restored = DiskMonitor(file: file)
        check(restored.ledger.days.count == monitor.ledger.days.count && restored.storageError.isEmpty, "real disk history is persisted and restored")
        let baselineBytes = restored.ledger.sum(Array(restored.ledger.days.keys)).bytes
        restored.setPaused(true); restored.sample()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        check(restored.lastSample == nil && restored.ledger.sum(Array(restored.ledger.days.keys)).bytes == baselineBytes, "paused monitor does not collect or alter restored history")
        restored.setPaused(false); restored.sample(); wait { restored.lastSample != nil }
        check(restored.ledger.sum(Array(restored.ledger.days.keys)).bytes == baselineBytes, "resume establishes a new baseline without backfill")
        let corruptFile = directory.appendingPathComponent("corrupt.json"), corrupt = Data("not valid history".utf8)
        try corrupt.write(to: corruptFile)
        let broken = DiskMonitor(file: corruptFile); broken.save()
        let preserved = try Data(contentsOf: corruptFile)
        check(preserved == corrupt && !broken.storageError.isEmpty, "corrupt disk history is preserved verbatim and writes are stopped")
        let futureFile = directory.appendingPathComponent("future.json")
        var future = DiskLedger(); future.version = 99
        let futureData = try JSONEncoder().encode(future); try futureData.write(to: futureFile)
        let newer = DiskMonitor(file: futureFile); newer.save()
        let futurePreserved = try Data(contentsOf: futureFile)
        check(futurePreserved == futureData && !newer.storageError.isEmpty, "future-version disk history cannot be overwritten by older code")
        check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("ledger.json").path), "disk persistence never creates or rewrites network history")
        print("All 10 disk integration checks passed.")
    }
}
