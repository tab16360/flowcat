import AppKit
import Combine
import UserNotifications

final class DiskAlertController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var preferences: DiskAlertPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "diskWriteAlertPreferences") }
            engine.clear()
        }
    }
    @Published private(set) var memory: DiskAlertMemory
    @Published var notificationStatus = "尚未申请系统通知；提醒仍会显示在这里。"
    @Published var persistenceError = ""
    @Published var deliveryError = ""
    @Published var selectedPath: String?
    var onOpen: (() -> Void)?
    private(set) var engine = DiskAlertEngine()
    private let file: URL
    private let defaults: UserDefaults
    private var writable = true
    init(file: URL, defaults: UserDefaults = .standard) {
        self.file = file; self.defaults = defaults
        preferences = defaults.data(forKey: "diskWriteAlertPreferences").flatMap { try? JSONDecoder().decode(DiskAlertPreferences.self, from: $0) } ?? DiskAlertPreferences()
        if FileManager.default.fileExists(atPath: file.path) {
            if let data = try? Data(contentsOf: file), let value = try? JSONDecoder().decode(DiskAlertMemory.self, from: data) { memory = value }
            else { memory = DiskAlertMemory(); writable = false }
        } else { memory = DiskAlertMemory() }
        super.init()
        if !writable { persistenceError = "提醒记录无法读取，已保留原文件并停止覆盖。" }
    }
    func configureNotifications() { UNUserNotificationCenter.current().delegate = self; refreshPermission() }
    func refreshPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationStatus = settings.authorizationStatus == .authorized ? "系统通知已允许。" : settings.authorizationStatus == .denied ? "系统通知未允许；可在系统设置中开启，面板内提醒仍有效。" : "尚未申请系统通知；提醒仍会显示在这里。"
            }
        }
    }
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.notificationStatus = "申请通知失败：" + error.localizedDescription } }
            else { self?.refreshPermission() }
        }
    }
    func resetContinuity() { engine.resetContinuity() }
    func ingest(from start: Date, to end: Date, processes: [String: DiskProcessUsage], daily: [String: DiskProcessUsage]) {
        guard preferences.enabled else { return }
        var updated = memory
        let alerts = engine.ingest(from: start, to: end, processes: processes, daily: daily, preferences: preferences, memory: &updated)
        guard !alerts.isEmpty else { return }
        memory = updated; save()
        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.name + " · " + alert.kind.title
            content.body = summary(alert)
            content.userInfo = ["path": alert.path]
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                guard settings.authorizationStatus == .authorized else { return }
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)) { [weak self] error in
                    DispatchQueue.main.async { self?.deliveryError = error.map { "系统通知发送失败，提醒已保留在面板：" + $0.localizedDescription } ?? "" }
                }
            }
        }
    }
    func summary(_ alert: DiskWriteAlert) -> String {
        switch alert.kind {
        case .sustained: return "最近 10 个完整分钟写入 \(diskVolume(alert.bytes))，其中至少 8 分钟达到速率阈值。"
        case .hourly: return "最近一小时已观测写入 \(diskVolume(alert.bytes))，达到设置预算。"
        case .daily: return "今日已观测写入 \(diskVolume(alert.bytes))，达到设置预算。"
        }
    }
    func snooze(_ path: String) { preferences.snoozedUntil[path] = Date().addingTimeInterval(3600) }
    func save() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(memory).write(to: file, options: .atomic); persistenceError = ""
        } catch { persistenceError = "提醒保存失败：" + error.localizedDescription }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            self?.selectedPath = response.notification.request.content.userInfo["path"] as? String
            self?.onOpen?()
        }
        completionHandler()
    }
}
