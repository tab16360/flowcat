import Foundation
import Darwin

struct Bytes: Codable, Equatable {
    var received: UInt64 = 0
    var sent: UInt64 = 0
    var total: UInt64 { received + sent }
    mutating func add(_ other: Bytes) { received += other.received; sent += other.sent }
    func difference(from old: Bytes) -> Bytes {
        Bytes(received: received >= old.received ? received - old.received : 0,
              sent: sent >= old.sent ? sent - old.sent : 0)
    }
}
struct ProcessCounter: Codable {
    var name: String
    var bytes: Bytes
}
struct LANExcludedTotal: Codable {
    var bytes = Bytes()
    var seconds: Double = 0
    mutating func add(_ other: LANExcludedTotal) { bytes.add(other.bytes); seconds += other.seconds }
}
struct DayRecord: Codable {
    var physical = Bytes()
    var processes: [String: Bytes] = [:]
    var monitoredSeconds: Double = 0
    var breakdown: TrafficBreakdown? = nil
    var withoutLAN: LANExcludedTotal? = nil
}
struct NetworkContext: Equatable {
    var key: String
    var name: String
    var identified: Bool
}
struct NetworkHistory: Codable {
    var name: String
    var days: [String: DayRecord] = [:]
}
struct Ledger: Codable {
    var version = 5
    var firstStarted: Date
    var days: [String: DayRecord] = [:]
    var networks: [String: NetworkHistory] = [:]
    init(firstStarted: Date = Date()) { self.firstStarted = firstStarted }
    enum CodingKeys: String, CodingKey { case version, firstStarted, days, networks }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstStarted = try container.decode(Date.self, forKey: .firstStarted)
        days = try container.decode([String: DayRecord].self, forKey: .days)
        networks = try container.decodeIfPresent([String: NetworkHistory].self, forKey: .networks) ?? [:]
        networks = networks.filter { $0.key.hasPrefix("wifi:") }
        for key in networks.keys {
            networks[key]?.name = String(key.dropFirst(5))
        }
    }
    mutating func add(day: String, physical: Bytes, processes: [String: Bytes], seconds: Double,
                      network: NetworkContext = NetworkContext(key: "__all__", name: "全部网络", identified: false),
                      breakdown: TrafficBreakdown? = nil) {
        // Subtract only observed physical-interface LAN deltas from the same interval.
        // Clamp each direction independently; never infer older intervals from aggregate history.
        let withoutLAN = breakdown.map { LANExcludedTotal(bytes: physical.difference(from: $0.local), seconds: seconds) }
        var record = days[day] ?? DayRecord()
        record.physical.add(physical)
        record.monitoredSeconds += seconds
        for (name, value) in processes {
            var bytes = record.processes[name] ?? Bytes()
            bytes.add(value)
            record.processes[name] = bytes
        }
        if let breakdown { var value = record.breakdown ?? TrafficBreakdown(); value.add(breakdown); record.breakdown = value }
        if let withoutLAN { var value = record.withoutLAN ?? LANExcludedTotal(); value.add(withoutLAN); record.withoutLAN = value }
        days[day] = record
        guard network.identified, network.key.hasPrefix("wifi:") else { return }
        var history = networks[network.key] ?? NetworkHistory(name: network.name)
        history.name = network.name
        var netDay = history.days[day] ?? DayRecord()
        netDay.physical.add(physical); netDay.monitoredSeconds += seconds
        for (name, value) in processes {
            var bytes = netDay.processes[name] ?? Bytes(); bytes.add(value); netDay.processes[name] = bytes
        }
        if let breakdown { var value = netDay.breakdown ?? TrafficBreakdown(); value.add(breakdown); netDay.breakdown = value }
        if let withoutLAN { var value = netDay.withoutLAN ?? LANExcludedTotal(); value.add(withoutLAN); netDay.withoutLAN = value }
        history.days[day] = netDay; networks[network.key] = history
    }
    func sum(keys: [String], networkName: String? = nil) -> DayRecord {
        var result = DayRecord()
        let sources: [[String: DayRecord]] = networkName.map { selected in
            networks.values.filter { $0.name == selected }.map(\.days)
        } ?? [days]
        for source in sources { for key in keys {
            guard let day = source[key] else { continue }
            result.physical.add(day.physical)
            result.monitoredSeconds += day.monitoredSeconds
            if let estimate = day.withoutLAN { var value = result.withoutLAN ?? LANExcludedTotal(); value.add(estimate); result.withoutLAN = value }
            if let breakdown = day.breakdown { var value = result.breakdown ?? TrafficBreakdown(); value.add(breakdown); result.breakdown = value }
            for (name, bytes) in day.processes {
                var value = result.processes[name] ?? Bytes()
                value.add(bytes)
                result.processes[name] = value
            }
        } }
        return result
    }
}
enum PanelLayout {
    static func size(screenWidth: Double, availableHeight: Double) -> (width: Double, height: Double) {
        (min(460, max(240, screenWidth - 24)), min(640, max(240, availableHeight - 28)))
    }
}
enum Parsers {
    static func processes(_ text: String) -> [String: ProcessCounter] {
        var result: [String: ProcessCounter] = [:]
        let header = text.split(separator: "\n").first?.split(separator: ",", omittingEmptySubsequences: false) ?? []
        let receivedIndex = header.firstIndex(of: "bytes_in") ?? 1
        let sentIndex = header.firstIndex(of: "bytes_out") ?? 2
        for line in text.split(separator: "\n") {
            let values = line.split(separator: ",", omittingEmptySubsequences: false)
            guard !values[0].contains("<->"), values.count > max(receivedIndex, sentIndex),
                  let separator = values[0].lastIndex(of: "."),
                  Int(values[0][values[0].index(after: separator)...]) != nil,
                  let received = UInt64(values[receivedIndex]), let sent = UInt64(values[sentIndex]) else { continue }
            result[String(values[0])] = ProcessCounter(name: String(values[0][..<separator]),
                bytes: Bytes(received: received, sent: sent))
        }
        return result
    }
    static func interfaces(_ text: String) -> [String: Bytes] {
        var result: [String: Bytes] = [:]
        for line in text.split(separator: "\n") {
            let values = line.split(whereSeparator: { $0.isWhitespace })
            guard values.count >= 10, values[0].hasPrefix("en"), values[2].hasPrefix("<Link#"),
                  let received = UInt64(values[6]), let sent = UInt64(values[9]) else { continue }
            result[String(values[0])] = Bytes(received: received, sent: sent)
        }
        return result
    }
}
enum DateKeys {
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    // Assign each short interval to its ending day. Midnight uncertainty is <= polling interval.
    static func keys(period: Int, now: Date, available: [String], calendar: Calendar = .current) -> [String] {
        switch period {
        case 1: return [day(calendar.date(byAdding: .day, value: -1, to: now)!, calendar: calendar)]
        case 2: return available.filter { $0.hasPrefix(String(day(now, calendar: calendar).prefix(7))) }
        default: return [day(now, calendar: calendar)]
        }
    }
}
func volume(_ bytes: UInt64) -> String {
    let value = Double(bytes)
    for (unit, divisor) in [("GB", 1e9), ("MB", 1e6), ("KB", 1e3)] {
        if value >= divisor { return String(format: "%.2f %@", value / divisor, unit) }
    }
    return "\(bytes) B"
}

// Classify presentation only; never subtract relayed bytes or rewrite historical counters.
enum ProcessTraffic {
    static func isRelay(_ name: String) -> Bool {
        let name = name.lowercased()
        let known = ["verge-mihomo", "mihomo", "clash", "clash verge", "clash verge rev",
                     "clashx", "clashx pro", "clash meta", "tailscale", "proxifier",
                     "sing-box", "singbox", "surge", "surge helper", "openvpn", "wireguard"]
        return known.contains(name) || name == "io.tailscale.ipn.macsys.network-extension"
    }
    static func rows(_ processes: [String: Bytes], relay: Bool) -> [(String, Bytes)] {
        processes.filter { isRelay($0.key) == relay }.map { ($0.key, $0.value) }
    }
}

enum TrafficScope: Int { case all, internet, local }
struct TrafficBreakdown: Codable {
    var internet = Bytes()
    var local = Bytes()
    var internetProcesses: [String: Bytes] = [:]
    var localProcesses: [String: Bytes] = [:]
    var seconds: Double = 0
    mutating func add(_ other: TrafficBreakdown) {
        internet.add(other.internet); local.add(other.local); seconds += other.seconds
        for (name, bytes) in other.internetProcesses { var b = internetProcesses[name] ?? Bytes(); b.add(bytes); internetProcesses[name] = b }
        for (name, bytes) in other.localProcesses { var b = localProcesses[name] ?? Bytes(); b.add(bytes); localProcesses[name] = b }
    }
}
extension DayRecord {
    func scoped(_ scope: TrafficScope) -> DayRecord {
        guard scope != .all else { return self }
        var result = DayRecord()
        result.physical = scope == .internet ? breakdown?.internet ?? Bytes() : breakdown?.local ?? Bytes()
        result.processes = scope == .internet ? breakdown?.internetProcesses ?? [:] : breakdown?.localProcesses ?? [:]
        result.monitoredSeconds = breakdown?.seconds ?? 0
        result.breakdown = breakdown
        return result
    }
}
struct ConnectionCounter {
    var processKey: String
    var processName: String
    var scope: TrafficScope
    var bytes: Bytes
}
enum ConnectionTraffic {
    static func addressScope(_ address: String, localSubnets: [LocalSubnet] = []) -> TrafficScope? {
        guard !address.isEmpty else { return nil }
        let ip = String(address.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)[0])
        if localSubnets.contains(where: { $0.contains(ip) }) { return .local }
        if ip.contains(":") {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard inet_pton(AF_INET6, ip, &bytes) == 1 else { return nil }
            if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 255 && bytes[11] == 255 {
                return addressScope(bytes.suffix(4).map(String.init).joined(separator: "."), localSubnets: localSubnets)
            }
            if bytes[0] & 0xfe == 0xfc || (bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80) { return .local }
            if bytes[0] == 0xff && bytes[1] & 0x0f == 2 { return .local }
            guard bytes[0] & 0xe0 == 0x20, !(bytes[0...3] == [0x20, 0x01, 0x0d, 0xb8]) else { return nil }
            return .internet
        }
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        let b = parts.compactMap { UInt8($0) }
        guard parts.count == 4, b.count == 4 else { return nil }
        if b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168) || (b[0] == 169 && b[1] == 254) || b[0] == 224 { return .local }
        // Unspecified, loopback, CGNAT/overlay, benchmark/fake-IP and documentation ranges are not public internet.
        if b[0] == 0 || b[0] == 127 || b[0] >= 224 || (b[0] == 100 && (64...127).contains(b[1])) || (b[0] == 198 && (18...19).contains(b[1])) || (b[0] == 192 && b[1] == 0) || (b[0] == 198 && b[1] == 51 && b[2] == 100) || (b[0] == 203 && b[1] == 0 && b[2] == 113) { return nil }
        return .internet
    }
    static func parse(_ text: String, localSubnets: [LocalSubnet] = []) -> [String: ConnectionCounter] {
        var result: [String: ConnectionCounter] = [:]
        let lines = text.split(separator: "\n")
        guard let first = lines.first else { return result }
        let header = first.split(separator: ",", omittingEmptySubsequences: false)
        guard let interfaceIndex = header.firstIndex(of: "interface"), let receivedIndex = header.firstIndex(of: "bytes_in"), let sentIndex = header.firstIndex(of: "bytes_out") else { return result }
        var processKey = "", processName = ""
        for line in lines.dropFirst() {
            let values = line.split(separator: ",", omittingEmptySubsequences: false)
            guard let name = values.first else { continue }
            if !name.contains("<->") {
                processKey = ""; processName = ""
                if let separator = name.lastIndex(of: "."), Int(name[name.index(after: separator)...]) != nil {
                    processKey = String(name); processName = String(name[..<separator])
                }
                continue
            }
            guard !processKey.isEmpty, values.count > max(interfaceIndex, max(receivedIndex, sentIndex)),
                let received = UInt64(values[receivedIndex]), let sent = UInt64(values[sentIndex]) else { continue }
            let interface = values[interfaceIndex]
            guard interface.hasPrefix("en"), Int(interface.dropFirst(2)) != nil,
                let remote = name.components(separatedBy: "<->").last else { continue }
            let separator: Character = name.hasPrefix("tcp6 ") || name.hasPrefix("udp6 ") ? "." : ":"
            guard let port = remote.lastIndex(of: separator), let scope = addressScope(String(remote[..<port]), localSubnets: localSubnets) else { continue }
            let key = processKey + "|" + String(name) + "|" + String(interface)
            var bytes = result[key]?.bytes ?? Bytes(); bytes.add(Bytes(received: received, sent: sent))
            result[key] = ConnectionCounter(processKey: processKey, processName: processName, scope: scope, bytes: bytes)
        }
        return result
    }
    static func delta(current: [String: ConnectionCounter], previous: [String: ConnectionCounter], seconds: Double, names: [String: String]) -> TrafficBreakdown {
        var result = TrafficBreakdown(); result.seconds = seconds
        for (key, c) in current {
            guard let old = previous[key], old.scope == c.scope else { continue }
            let bytes = c.bytes.difference(from: old.bytes)
            guard bytes.total > 0 else { continue }
            let pid = c.processKey.split(separator: ".").last.map(String.init) ?? ""
            let name = names[pid] ?? c.processName
            if c.scope == .internet {
                result.internet.add(bytes)
                var b = result.internetProcesses[name] ?? Bytes(); b.add(bytes); result.internetProcesses[name] = b
            } else {
                result.local.add(bytes)
                var b = result.localProcesses[name] ?? Bytes(); b.add(bytes); result.localProcesses[name] = b
            }
        }
        return result
    }
}

struct LocalSubnet {
    var address: [UInt8]
    var prefix: Int
    static func bytes(_ text: String) -> [UInt8]? {
        guard !text.isEmpty else { return nil }
        let text = String(text.split(separator: "%", maxSplits: 1)[0])
        var bytes = [UInt8](repeating: 0, count: text.contains(":") ? 16 : 4)
        guard inet_pton(bytes.count == 16 ? AF_INET6 : AF_INET, text, &bytes) == 1 else { return nil }
        return bytes
    }
    func contains(_ ip: String) -> Bool {
        guard let bytes = Self.bytes(ip), bytes.count == address.count, prefix > 0, prefix <= bytes.count * 8 else { return false }
        for i in 0..<bytes.count {
            let bits = min(8, max(0, prefix - i * 8))
            let mask = bits == 0 ? UInt8(0) : UInt8(255 << (8 - bits) & 255)
            if bytes[i] & mask != address[i] & mask { return false }
        }
        return true
    }
    static func parse(_ text: String) -> [LocalSubnet] {
        var physical = false, result: [LocalSubnet] = []
        for line in text.split(separator: "\n") {
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                let name = line.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
                physical = name.hasPrefix("en") && Int(name.dropFirst(2)) != nil
            }
            guard physical else { continue }
            let words = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard words.count >= 4, let bytes = bytes(words[1]) else { continue }
            if words[0] == "inet6", let i = words.firstIndex(of: "prefixlen"), words.count > i + 1, let prefix = Int(words[i + 1]), (1...128).contains(prefix) {
                result.append(LocalSubnet(address: bytes, prefix: prefix))
            } else if words[0] == "inet", let i = words.firstIndex(of: "netmask"), words.count > i + 1, let mask = UInt32(words[i + 1].replacingOccurrences(of: "0x", with: ""), radix: 16), mask > 0 {
                result.append(LocalSubnet(address: bytes, prefix: mask.nonzeroBitCount))
            }
        }
        return result
    }
}
