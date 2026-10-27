import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: \(label)") }
    print("PASS: \(label)")
}
let nettop = """
,bytes_in,bytes_out,
UURemote.29337,275271547,4816332,
Codex (Service).29890,3898336,4942778,
node.123,10,20,
node.124,30,40,
wrong,nope,nope,
"""
let parsed = Parsers.processes(nettop)
expect(parsed.count == 4, "nettop skips headers and malformed rows")
expect(parsed["UURemote.29337"]?.bytes.received == 275271547, "process byte counters")
expect(parsed["Codex (Service).29890"]?.name == "Codex (Service)", "process names containing spaces")
expect(parsed["node.123"] != nil && parsed["node.124"] != nil, "separate PID baselines")
let interfaces = """
Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
en0 1500 <Link#12> a0:78:17:00:00:00 100 0 5000000000 80 0 4000000000 0
en0 1500 192.168.1 192.168.1.2 100 - 5000000000 80 - 4000000000 -
lo0 16384 <Link#1> 00:00:00:00:00:00 50 0 200 50 0 200 0
utun4 1280 <Link#16> 00:00:00:00:00:00 10 0 50 10 0 60 0
en1 1500 <Link#13> 00:00:00:00:00:00 0 0 10 0 0 20 0
"""
let nets = Parsers.interfaces(interfaces)
expect(nets.count == 2, "exclude loopback, VPN and duplicate address rows")
expect(nets["en0"]?.total == 9000000000, "64-bit counters beyond 4 GB")
expect(Bytes(received: 120, sent: 70).difference(from: Bytes(received: 100, sent: 50)) == Bytes(received: 20, sent: 20), "interval deltas")
expect(Bytes(received: 1, sent: 2).difference(from: Bytes(received: 100, sent: 200)) == Bytes(), "counter reset does not create negative or gigantic traffic")
let formatter = ISO8601DateFormatter()
let date = formatter.date(from: "2026-10-10T12:00:00Z")!
var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
expect(DateKeys.keys(period: 0, now: date, available: [], calendar: calendar) == ["2026-10-10"], "today uses local calendar")
expect(DateKeys.keys(period: 1, now: date, available: [], calendar: calendar) == ["2026-10-09"], "yesterday date selection")
let monthStart = formatter.date(from: "2026-09-30T18:00:00Z")!
expect(DateKeys.keys(period: 1, now: monthStart, available: [], calendar: calendar) == ["2026-09-30"], "yesterday across month boundary")
var ledger = Ledger(firstStarted: date)
ledger.add(day: "2026-10-09", physical: Bytes(received: 100, sent: 20), processes: ["UU": Bytes(received: 100), "Tailscale": Bytes(received: 100)], seconds: 10)
ledger.add(day: "2026-10-10", physical: Bytes(received: 200, sent: 30), processes: ["UU": Bytes(received: 200)], seconds: 10)
ledger.add(day: "2026-09-30", physical: Bytes(received: 9999), processes: [:], seconds: 10)
let monthKeys = DateKeys.keys(period: 2, now: date, available: Array(ledger.days.keys), calendar: calendar)
let monthly = ledger.sum(keys: monthKeys)
expect(monthly.physical.total == 350, "month excludes previous month")
expect(monthly.processes["UU"]?.received == 300, "process monthly aggregate")
expect(monthly.physical.total != monthly.processes.values.reduce(0, { $0 + $1.total }), "physical total is independent of duplicated relay accounting")
expect(ledger.sum(keys: ["2026-10-08"]).physical.total == 0, "no fabricated pre-monitor history")
let data = try JSONEncoder().encode(ledger)
let restored = try JSONDecoder().decode(Ledger.self, from: data)
expect(restored.sum(keys: monthKeys).physical == monthly.physical, "history survives JSON round trip")
expect(volume(10000000000) == "10.0 GB", "decimal units match mobile data units")
expect(volume(180_000_000) == "180 MB" && volume(2_630_000_000) == "2.63 GB" && volume(9_996_000) == "10.0 MB", "volumes keep three significant digits")
Localization.shared.forced = .chinese
expect(coverageText(14_400) == "已记录 4 小时 0 分" && coverageText(90) == "已记录 1 分", "coverage text is shared by network and disk")
Localization.shared.forced = .english
expect(coverageText(14_400) == "Recorded 4h 0m" && DiskPeriod.seven.title == "Last 7 days", "English is available for shared labels")
Localization.shared.forced = .chinese
var hourly = Ledger(firstStarted: date)
hourly.add(day: "2026-10-10", physical: Bytes(received: 100), processes: [:], seconds: 10, network: NetworkContext(key: "wifi:Home", name: "Home", identified: true), breakdown: TrafficBreakdown(), hour: "1000")
hourly.add(day: "2026-10-10", physical: Bytes(received: 50), processes: [:], seconds: 10, hour: "1000")
expect(hourly.days["2026-10-10"]?.hours?["1000"]?.received == 150 && hourly.day("2026-10-10", networkName: "Home").hours?["1000"]?.received == 100, "hour buckets follow all-network and per-SSID totals")
expect(hourly.day("2026-10-10").hoursWithoutLAN?["1000"]?.received == 100, "hourly LAN estimate only covers intervals with a breakdown")
expect(DateKeys.keys(period: 3, now: date, available: [], calendar: calendar).count == 7, "network 7-day period includes today")
var classified = Ledger(firstStarted: date)
classified.add(day: "2026-10-09", physical: Bytes(received: 1000), processes: ["UU": Bytes(received: 800)], seconds: 10,
    network: NetworkContext(key: "wifi:RMB", name: "RMB", identified: true))
classified.add(day: "2026-10-10", physical: Bytes(received: 2000), processes: ["UU": Bytes(received: 1800)], seconds: 20,
    network: NetworkContext(key: "wifi:Phone1", name: "Phone1", identified: true))
classified.add(day: "2026-10-10", physical: Bytes(received: 500), processes: ["SSH": Bytes(received: 500)], seconds: 5,
    network: NetworkContext(key: "wifi:Phone2", name: "Phone2", identified: true))
classified.add(day: "2026-10-10", physical: Bytes(received: 300), processes: ["UU": Bytes(received: 300)], seconds: 3,
    network: NetworkContext(key: "__all__", name: "全部网络", identified: false))
expect(classified.sum(keys: ["2026-10-09", "2026-10-10"], networkName: "RMB").physical.total == 1000, "RMB traffic remains separate")
expect(classified.sum(keys: ["2026-10-10"], networkName: "Phone1").physical.total == 2000, "actual SSIDs remain separate")
expect(classified.sum(keys: ["2026-10-10"], networkName: "Phone1").processes["UU"]?.total == 1800, "per-SSID process traffic")
expect(classified.sum(keys: ["2026-10-10"], networkName: "RMB").physical.total == 0, "network filter respects selected date")
expect(classified.sum(keys: ["2026-10-10"]).physical.total == 2800, "all networks total does not double-count classified storage")
let classifiedRestored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(classified))
expect(classifiedRestored.sum(keys: ["2026-10-10"], networkName: "Phone1").physical.total == 2000, "SSID history persists")
var legacyJSON = try JSONSerialization.jsonObject(with: data) as! [String: Any]
legacyJSON.removeValue(forKey: "networks"); legacyJSON["version"] = 1
let legacy = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: legacyJSON))
expect(legacy.sum(keys: monthKeys).physical.total == 350 && legacy.networks.isEmpty, "upgrade preserves old totals without adding a fake network")
expect(legacy.sum(keys: monthKeys, networkName: "Phone1").physical.total == 0, "upgrade does not fabricate historical network attribution")
let smallPanel = PanelLayout.size(screenWidth: 1024, availableHeight: 480)
expect(smallPanel.height == 452 && smallPanel.width == 460, "popup fits a short display")
let narrowPanel = PanelLayout.size(screenWidth: 400, availableHeight: 800)
expect(narrowPanel.width == 376 && narrowPanel.height == 640, "popup fits display width and caps height")
expect(classified.networks["__all__"] == nil, "unidentified traffic only updates all-network totals")
var aliasedJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(classified)) as! [String: Any]
var oldNetworks = aliasedJSON["networks"] as! [String: Any]
var renamed = oldNetworks["wifi:Phone1"] as! [String: Any]; renamed["name"] = "Former manual label"
oldNetworks["wifi:Phone1"] = renamed
oldNetworks["legacy"] = renamed
aliasedJSON["networks"] = oldNetworks
let normalized = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: aliasedJSON))
expect(normalized.networks["wifi:Phone1"]?.name == "Phone1", "upgrade restores the exact stored SSID rather than manual labels")
expect(normalized.networks["legacy"] == nil && normalized.sum(keys: ["2026-10-10"]).physical.total == 2800, "legacy classification hidden with original totals intact")
func release(_ version: String, url: String? = nil, draft: Bool = false, prerelease: Bool = false) -> ReleaseInfo {
    let name = "FlowCat-\(version)-arm64.zip"
    return ReleaseInfo(tag_name: "v\(version)", body: nil, draft: draft, prerelease: prerelease,
        assets: [ReleaseInfo.Asset(name: name, browser_download_url: URL(string: url ?? "https://github.com/tab16360/flowcat/releases/download/v\(version)/\(name)")!)])
}
expect(release("1.3.10").isNewer(than: "1.3.9"), "updates compare numeric version components")
expect(!release("1.3.4").isNewer(than: "1.3.5"), "updates never offer a downgrade")
expect(!release("1.3.5").isNewer(than: "1.3.5"), "current version does not offer an update")
expect(release("1.3.5").downloadURL != nil, "updates select the matching arm64 asset")
expect(release("1.3.5", url: "https://example.com/package.zip").downloadURL == nil, "updates reject a foreign download host")
expect(release("1.3.5", url: "https://github.com/other/repo/releases/download/v1.3.5/FlowCat-1.3.5-arm64.zip").downloadURL == nil, "updates reject assets from another repository")
expect(release("1.3.5", prerelease: true).downloadURL == nil && !release("1.3.5", draft: true).isNewer(than: "1.3.4"), "updates exclude drafts and prereleases")
expect(!ReleaseInfo.validVersion("1.3.5-beta") && !ReleaseInfo.validVersion("1..5"), "updates reject malformed stable versions")
let relayHistory: [String: Bytes] = [
    "verge-mihomo": Bytes(received: 100, sent: 100),
    "Google Chrome": Bytes(received: 100),
    "io.tailscale.ipn.macsys.network-extension": Bytes(sent: 50),
    "My VPN Notes": Bytes(received: 5)
]
expect(ProcessTraffic.rows(relayHistory, relay: false).count == 2, "application view excludes known forwarding processes")
expect(ProcessTraffic.rows(relayHistory, relay: true).count == 2, "relay view retains proxy and tunnel counters")
expect(!ProcessTraffic.isRelay("My VPN Notes") && !ProcessTraffic.isRelay("clash-game"), "unrelated names are not hidden by substring matching")
expect(ProcessTraffic.isRelay("Clash Verge") && ProcessTraffic.isRelay("MIHOMO"), "known app and core names use case-insensitive classification")
expect(ProcessTraffic.rows(relayHistory, relay: false).first(where: { $0.0 == "Google Chrome" })?.1.received == 100 && relayHistory["verge-mihomo"]?.total == 200, "presentation preserves app bytes and original relay history without redistribution")
let expanded = """
,interface,bytes_in,bytes_out,
kernel_task.0,,1000,2000,
tcp4 192.168.20.181:50001<->192.168.20.2:445,en0,1000,2000,
Chrome.123,,500,600,
tcp4 192.168.20.181:50002<->8.8.8.8:443,en0,500,600,
tcp4 127.0.0.1:50003<->127.0.0.1:7890,lo0,700,800,
tcp4 198.18.0.1:50004<->198.18.0.2:443,utun1024,900,1000,
tcp6 240e::1.50005<->2606:4700::1111.443,en0,50,60,
udp4 *:5353<->*:*,en0,20,30,
"""
let expandedProcesses = Parsers.processes(expanded)
expect(expandedProcesses.count == 2 && expandedProcesses["Chrome.123"]?.bytes.sent == 600, "expanded nettop retains process summaries without counting connection rows twice")
let connections = ConnectionTraffic.parse(expanded)
expect(connections.count == 3, "connection scope excludes loopback, fake-IP tunnel and unknown UDP peer")
expect(connections.values.filter { $0.scope == .local }.count == 1, "SMB private destination is local traffic")
expect(connections.values.filter { $0.scope == .internet }.count == 2, "global IPv4 and IPv6 destinations are internet traffic")
expect(ConnectionTraffic.addressScope("10.0.0.1") == .local && ConnectionTraffic.addressScope("172.31.1.2") == .local && ConnectionTraffic.addressScope("192.168.1.2") == .local, "all RFC1918 private ranges classified local")
expect(ConnectionTraffic.addressScope("fe80::1%en0") == .local && ConnectionTraffic.addressScope("fd12::1") == .local && ConnectionTraffic.addressScope("224.0.0.251") == .local, "link-local, IPv6 ULA and local multicast classified local")
expect(ConnectionTraffic.addressScope("127.0.0.1") == nil && ConnectionTraffic.addressScope("::1") == nil && ConnectionTraffic.addressScope("100.90.79.37") == nil && ConnectionTraffic.addressScope("198.18.0.30") == nil, "loopback overlay and fake-IP excluded from internet estimate")
expect(ConnectionTraffic.addressScope("") == nil && ConnectionTraffic.addressScope("*") == nil && ConnectionTraffic.addressScope("999.1.2.3") == nil && ConnectionTraffic.addressScope("2001:db8::1") == nil, "malformed and reserved addresses do not become internet")
expect(ConnectionTraffic.addressScope("::ffff:192.168.1.2") == .local && ConnectionTraffic.addressScope("::ffff:8.8.8.8") == .internet, "IPv4-mapped IPv6 classified by embedded address")
var newerConnections = connections
for key in newerConnections.keys { newerConnections[key]!.bytes.add(Bytes(received: 10, sent: 20)) }
let breakdown = ConnectionTraffic.delta(current: newerConnections, previous: connections, seconds: 10, names: ["123": "Google Chrome"])
expect(breakdown.local == Bytes(received: 10, sent: 20) && breakdown.internet == Bytes(received: 20, sent: 40), "socket baselines accumulate interval traffic by address scope")
expect(breakdown.localProcesses["kernel_task"]?.sent == 20 && breakdown.internetProcesses["Google Chrome"]?.sent == 40, "kernel SMB and app helper attribution survive classification")
expect(ConnectionTraffic.delta(current: connections, previous: [:], seconds: 10, names: [:]).internet.total == 0, "new connections establish baseline rather than backfilling lifetime bytes")
expect(ConnectionTraffic.delta(current: connections, previous: newerConnections, seconds: 10, names: [:]).local.total == 0, "connection counter reset cannot inflate traffic")
var scopedLedger = Ledger(firstStarted: date)
scopedLedger.add(day: "2026-10-10", physical: Bytes(sent: 1000), processes: ["kernel_task": Bytes(sent: 900)], seconds: 10,
 network: NetworkContext(key: "wifi:Home", name: "Home", identified: true), breakdown: breakdown)
let scopedRecord = scopedLedger.sum(keys: ["2026-10-10"], networkName: "Home")
expect(scopedRecord.scoped(.all).physical.sent == 1000 && scopedRecord.scoped(.local).physical.sent == 20 && scopedRecord.scoped(.internet).physical.sent == 40, "SSID and date filters preserve physical total separately from connection estimates")
expect(scopedRecord.scoped(.local).monitoredSeconds == 10 && scopedRecord.scoped(.local).processes["kernel_task"]?.sent == 20, "scoped coverage and process ranking use the same classified intervals")
let scopedRestored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(scopedLedger))
expect(scopedRestored.sum(keys: ["2026-10-10"]).breakdown?.local.sent == 20, "scope estimates survive history round trip")
expect(restored.sum(keys: monthKeys).breakdown == nil && restored.sum(keys: monthKeys).scoped(.internet).monitoredSeconds == 0, "old history cannot fabricate internet classification or coverage")
scopedLedger.add(day: "2026-10-10", physical: Bytes(sent: 3000), processes: [:], seconds: 30)
expect(scopedLedger.sum(keys: ["2026-10-10"]).monitoredSeconds == 40 && scopedLedger.sum(keys: ["2026-10-10"]).scoped(.internet).monitoredSeconds == 10, "mixed old and new history reports classification coverage without rewriting old totals")
expect(scopedRecord.withoutLAN?.bytes.sent == 980 && scopedRecord.withoutLAN?.seconds == 10, "LAN exclusion uses same-interval physical total minus observed LAN")
expect(scopedRestored.sum(keys: ["2026-10-10"]).withoutLAN?.bytes.sent == 980, "LAN-excluded total and coverage survive persistence")
expect(restored.sum(keys: monthKeys).withoutLAN == nil, "legacy histories show unavailable LAN-excluded totals rather than invented zero")
let mixedLAN = scopedLedger.sum(keys: ["2026-10-10"])
expect(mixedLAN.withoutLAN?.bytes.sent == 980 && mixedLAN.withoutLAN?.seconds == 10 && mixedLAN.physical.sent == 4000, "legacy and new intervals keep separate estimation coverage and original totals")
expect(mixedLAN.processes["kernel_task"]?.sent == 900, "total LAN toggle never filters app counters")
var lanIntervals = Ledger(firstStarted: date)
var largeLAN = TrafficBreakdown(); largeLAN.local = Bytes(received: 400, sent: 20)
lanIntervals.add(day: "2026-10-10", physical: Bytes(received: 200, sent: 100), processes: [:], seconds: 10, network: NetworkContext(key: "wifi:Home", name: "Home", identified: true), breakdown: largeLAN)
expect(lanIntervals.days["2026-10-10"]?.withoutLAN?.bytes == Bytes(received: 0, sent: 80), "LAN subtraction clamps download and upload independently without underflow")
lanIntervals.add(day: "2026-10-10", physical: Bytes(received: 100, sent: 50), processes: [:], seconds: 10, network: NetworkContext(key: "wifi:Other", name: "Other", identified: true), breakdown: TrafficBreakdown())
expect(lanIntervals.sum(keys: ["2026-10-10"]).withoutLAN?.bytes == Bytes(received: 100, sent: 130), "LAN subtraction clamps per interval before aggregation")
expect(lanIntervals.sum(keys: ["2026-10-10"], networkName: "Home").withoutLAN?.bytes == Bytes(received: 0, sent: 80) && lanIntervals.sum(keys: ["2026-10-10"], networkName: "Other").withoutLAN?.bytes.received == 100, "LAN-excluded totals remain separated by actual Wi-Fi")
let subnetText = """
en0: flags=8863<UP> mtu 1500
    inet 192.168.20.181 netmask 0xffffff00 broadcast 192.168.20.255
    inet6 240e:445:50:bc51::1 prefixlen 64 autoconf
utun1: flags=8051<UP> mtu 1380
    inet6 2606:4700::1 prefixlen 32
"""
let localSubnets = LocalSubnet.parse(subnetText)
expect(localSubnets.count == 2, "only physical-interface subnets affect locality")
expect(ConnectionTraffic.addressScope("240e:445:50:bc51::2", localSubnets: localSubnets) == .local, "global IPv6 on the same LAN subnet is not internet")
expect(ConnectionTraffic.addressScope("240e:445:50:bc52::2", localSubnets: localSubnets) == .internet && ConnectionTraffic.addressScope("2606:4700::1111", localSubnets: localSubnets) == .internet, "different global IPv6 subnet and tunnel prefixes do not masquerade as LAN")
expect(LocalSubnet(address: [192,168,20,181], prefix: 24).contains("192.168.20.255") && !LocalSubnet(address: [192,168,20,181], prefix: 24).contains("192.168.21.1"), "IPv4 subnet masks respect boundary and broadcast address")
expect(!UpdateArchive.validName("/流量喵.app/Contents/Info.plist") && !UpdateArchive.validName("流量喵.app/../escape"), "installer rejects absolute and escaping ZIP paths")
expect(!UpdateArchive.validName("流量喵.app/Contents/./Info.plist") && !UpdateArchive.validName("流量喵.app//Contents/Info.plist"), "installer rejects noncanonical ZIP paths")
expect(UpdateArchive.validName("流量喵.app/Contents/MacOS/FlowCat") && UpdateArchive.validName("__MACOSX/流量喵.app/._Contents"), "installer accepts Unicode app names and ditto metadata")
expect(!UpdateArchive.validName("Other.app/Contents/Info.plist") && !UpdateArchive.validName("流量喵.app/Contents\\..\\escape"), "installer rejects other app bundles and backslash paths")
expect(UpdateArchive.checksum(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "installer SHA256 matches known digest")
expect(!UpdateInstaller.validTeamTransition(from: "TRUSTED", to: nil) && !UpdateInstaller.validTeamTransition(from: "TRUSTED", to: "OTHER"), "signed app updates cannot drop or change signing team")
expect(UpdateInstaller.validTeamTransition(from: "TRUSTED", to: "TRUSTED") && UpdateInstaller.validTeamTransition(from: nil, to: "TRUSTED"), "installer preserves signed trust and allows transition from ad hoc to Developer ID")
expect(release("1.4.0").installationAsset == nil, "missing digest and size cannot trigger installation")
expect(release("1.4.0", url: "https://github.com/tab16360/flowcat/releases/download/v1.4.0/FlowCat-1.4.0-arm64.zip?unexpected=1").downloadURL == nil, "updates reject altered asset URL queries")
expect(release("1.4.0", url: "https://github.com:8443/tab16360/flowcat/releases/download/v1.4.0/FlowCat-1.4.0-arm64.zip").downloadURL == nil, "updates reject nonstandard asset ports")
expect(!UpdateInstaller.validWorkspace(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")), "updater cleanup cannot target arbitrary user directories")
expect(UpdateInstaller.validWorkspace(UpdateInstaller.cacheRoot.appendingPathComponent(UUID().uuidString)), "updater workspace confined to UUID directory inside owned cache")
expect(!UpdateInstaller.validWorkspace(URL(string: "https://example.com/" + UUID().uuidString)!), "updater plan rejects network workspace URLs")


// Disk history: baselines, lifecycle, coverage, local-day boundaries and hardware semantics.
func diskCounter(_ key: String, _ read: UInt64, _ written: UInt64, group: String = "/Applications/Test.app") -> DiskProcessCounter {
    DiskProcessCounter(identity: key, group: group, usage: DiskProcessUsage(name: "Test", path: group, bytes: DiskBytes(read: read, written: written)))
}
var diskLedger = DiskLedger(firstStarted: date), accumulator = DiskAccumulator()
let baseline = diskCounter("10:100", 4_000_000_000, 8_000_000_000)
expect(accumulator.apply(DiskSnapshot(date: date, counters: [baseline.identity: baseline]), ledger: &diskLedger) == nil && diskLedger.days.isEmpty, "disk first observation only establishes baseline")
let next = diskCounter("10:100", 4_000_000_100, 8_000_000_200)
let nextTime = date.addingTimeInterval(10)
expect(accumulator.apply(DiskSnapshot(date: nextTime, counters: [next.identity: next]), ledger: &diskLedger) == DiskBytes(read: 100, written: 200), "disk accumulates only observed 64-bit counter deltas")
expect(diskLedger.sum(Array(diskLedger.days.keys)).seconds == 10, "disk coverage records observed seconds")
let reused = diskCounter("10:200", 9_000_000_000, 9_000_000_000)
expect(accumulator.apply(DiskSnapshot(date: date.addingTimeInterval(20), counters: [reused.identity: reused]), ledger: &diskLedger) == DiskBytes(), "reused PID with different start time cannot create a spike")
let reset = diskCounter("10:200", 1, 2)
expect(accumulator.apply(DiskSnapshot(date: date.addingTimeInterval(30), counters: [reset.identity: reset]), ledger: &diskLedger) == DiskBytes(), "reset disk counters do not wrap around")
expect(accumulator.apply(DiskSnapshot(date: date.addingTimeInterval(300), counters: [reused.identity: reused]), ledger: &diskLedger) == nil, "sleep and missed sampling intervals are not attributed")
accumulator.reset()
expect(accumulator.apply(DiskSnapshot(date: date.addingTimeInterval(310), counters: [reused.identity: reused]), ledger: &diskLedger) == nil, "pause and wake reset disk baseline")
_ = accumulator.apply(DiskSnapshot(date: date.addingTimeInterval(320), counters: [:], valid: false), ledger: &diskLedger)
expect(accumulator.apply(DiskSnapshot(date: date.addingTimeInterval(330), counters: [reused.identity: reused]), ledger: &diskLedger) == nil, "failed snapshot invalidates baseline rather than backfilling unknown writes")
var grouped = DiskLedger(firstStarted: date), groupAccumulator = DiskAccumulator()
let parent = diskCounter("20:100", 100, 100), helper = diskCounter("21:100", 50, 50)
_ = groupAccumulator.apply(DiskSnapshot(date: date, counters: [parent.identity: parent, helper.identity: helper]), ledger: &grouped)
let parent2 = diskCounter("20:100", 110, 130), helper2 = diskCounter("21:100", 55, 57)
_ = groupAccumulator.apply(DiskSnapshot(date: nextTime, counters: [parent2.identity: parent2, helper2.identity: helper2]), ledger: &grouped)
expect(grouped.sum(Array(grouped.days.keys)).processes.count == 1 && grouped.sum(Array(grouped.days.keys)).bytes == DiskBytes(read: 15, written: 37), "app and helper deltas group once without adding lifetime counters")
_ = groupAccumulator.apply(DiskSnapshot(date: date.addingTimeInterval(20), counters: [:]), ledger: &grouped)
expect(grouped.sum(Array(grouped.days.keys)).bytes.written == 37, "terminated processes retain recorded disk history")
let midnight = formatter.date(from: "2026-10-10T16:00:00Z")!
var split = DiskLedger(firstStarted: midnight.addingTimeInterval(-5))
split.add(from: midnight.addingTimeInterval(-5), to: midnight.addingTimeInterval(5), processes: ["app": DiskProcessUsage(name: "App", path: "/app", bytes: DiskBytes(read: 101, written: 203))], calendar: calendar)
expect(split.days["2026-10-10"]?.bytes == DiskBytes(read: 50, written: 101) && split.days["2026-10-11"]?.bytes == DiskBytes(read: 51, written: 102), "midnight splits integer disk bytes and preserves remainders")
expect(split.days.values.reduce(0) { $0+$1.seconds } == 10, "midnight split preserves exact coverage")
expect(split.days.values.reduce(0) { $0+$1.hours.count } == 2, "hourly trend is stored independently across local midnight")
let splitRoundTrip = try JSONDecoder().decode(DiskLedger.self, from: JSONEncoder().encode(split))
expect(splitRoundTrip.sum(Array(split.days.keys)).bytes == DiskBytes(read: 101, written: 203), "disk history and process metadata survive JSON round trip")
var dstCalendar = Calendar(identifier: .gregorian); dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
let dstBoundary = formatter.date(from: "2026-11-01T09:00:00Z")!
var dstHistory = DiskLedger()
dstHistory.add(from: dstBoundary.addingTimeInterval(-5), to: dstBoundary.addingTimeInterval(5), processes: ["x": DiskProcessUsage(name: "x", path: "x", bytes: DiskBytes(written: 101))], calendar: dstCalendar)
expect(dstHistory.days["2026-11-01"]?.hours.count == 2 && dstHistory.days["2026-11-01"]?.bytes.written == 101, "repeated DST hours have distinct absolute hour buckets")
expect(DiskPeriod.seven.keys(now: monthStart, date: date, available: [], calendar: calendar).count == 7 && DiskPeriod.seven.keys(now: monthStart, date: date, available: [], calendar: calendar).last == "2026-10-01", "seven-day window includes today across month boundary")
expect(DiskPeriod.thirty.keys(now: date, date: date, available: [], calendar: calendar).count == 30, "thirty-day window uses 30 local calendar days")
expect(DiskPeriod.date.keys(now: date, date: midnight, available: [], calendar: calendar) == ["2026-10-11"], "daily disk selection uses selected local date")
expect(DiskPeriod.all.keys(now: date, date: date, available: ["2026-10-10","2099-01-01","2026-09-01"], calendar: calendar) == ["2026-09-01","2026-10-10"], "all-time history excludes future date keys")
let hardwareFixture: [String: Any] = ["MediaName":"SSD", "Internal":true, "TotalSize":512_000_000_000, "SolidState":true, "SMARTStatus":"Verified", "SMARTDeviceSpecificKeysMayVaryNotGuaranteed":["TEMPERATURE":311, "PERCENTAGE_USED":3, "AVAILABLE_SPARE":100, "DATA_UNITS_WRITTEN_0":2, "DATA_UNITS_WRITTEN_1":0, "MEDIA_ERRORS_0":0, "POWER_ON_HOURS_0":1286]]
let hardwareDisk = DiskDevice.fromPlist(hardwareFixture, id: "disk0")
expect(hardwareDisk.status == .normal && hardwareDisk.temperature == 38 && hardwareDisk.enduranceUsed == 3, "hardware status, Kelvin temperature and endurance remain separate metrics")
expect(hardwareDisk.hostWritten == 1_024_000 && hardwareDisk.powerOnHours == 1286 && hardwareDisk.mediaErrors == 0, "NVMe data units convert to 512000 bytes and preserve zero error counts")
let unsupportedDisk = DiskDevice.fromPlist(["MediaName":"External", "SMARTStatus":"Not Supported"], id: "disk2")
expect(unsupportedDisk.status == .unavailable && unsupportedDisk.hostWritten == nil && unsupportedDisk.temperature == nil, "unsupported hardware shows unavailable instead of fabricated zero metrics or healthy state")
expect(DiskDevice.fromPlist(["SMARTStatus":"Failing"], id: "disk1").status == .warning, "hardware failing status is surfaced as a warning")
let largeFields: [String: Any] = ["SMARTDeviceSpecificKeysMayVaryNotGuaranteed": ["DATA_UNITS_WRITTEN_0":UInt64.max, "DATA_UNITS_WRITTEN_1":0, "DATA_UNITS_READ_0":1, "DATA_UNITS_READ_1":1, "PERCENTAGE_USED":120]]
let largeDisk = DiskDevice.fromPlist(largeFields, id: "disk0")
expect(largeDisk.hostWritten == nil && largeDisk.hostRead == nil && largeDisk.enduranceUsed == 120, "overflowing 128-bit hardware counters are unavailable and endurance may exceed 100 percent")
expect(DiskBytes(read: .max, written: 1).total == .max, "disk total uses saturating addition rather than crashing on overflow")
expect(diskVolume(1_500_000_000_000) == "1.50 TB", "disk history formats large totals in decimal TB")
expect(MenuBarSpeeds.columns(total: nil, network: nil, read: nil, write: nil).isEmpty, "all menu metrics disabled leaves icon only")
expect(MenuBarSpeeds.columns(total: "今 1 GB", network: "↓1 MB/s", read: nil, write: nil) == [["今 1 GB", "↓1 MB/s"]], "daily total and speed share a column in top-bottom order")
expect(MenuBarSpeeds.columns(total: "今 1 GB", network: nil, read: "1 MB/s", write: "2 MB/s") == [["今 1 GB"], ["读 1 MB/s", "写 2 MB/s"]], "disk column stays independent when total and disk are enabled")
expect(MenuBarSpeeds.columns(total: nil, network: "暂停", read: nil, write: nil) == [["暂停"]], "paused speed uses a single status row")
var pathLedger = Ledger(firstStarted: date)
pathLedger.processPaths["Example App"] = "/Applications/Example App.app"
let pathRestored = try JSONDecoder().decode(Ledger.self, from: JSONEncoder().encode(pathLedger))
var legacyPathObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(pathLedger)) as! [String: Any]
legacyPathObject.removeValue(forKey: "processPaths")
let legacyPathRestored = try JSONDecoder().decode(Ledger.self, from: JSONSerialization.data(withJSONObject: legacyPathObject))
expect(pathRestored.processPaths["Example App"] == "/Applications/Example App.app" && legacyPathRestored.processPaths.isEmpty, "process paths persist and legacy histories default to no recorded paths")
expect(ProcessLocation.existingURL("relative/path") == nil && ProcessLocation.existingURL("/no/such/FlowCat-application.app") == nil, "Finder navigation rejects relative or missing paths")
expect(ProcessLocation.existingURL("/System/Applications/Utilities/Terminal.app")?.path == "/System/Applications/Utilities/Terminal.app", "Finder navigation resolves an installed application bundle without launching it")
print("All core and disk checks passed.")
