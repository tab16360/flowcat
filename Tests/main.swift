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
expect(volume(10000000000) == "10.00 GB", "decimal units match mobile data units")
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
print("All 78 checks passed.")
