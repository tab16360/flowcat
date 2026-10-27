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
    @Published var notificationStatus = tr("Notifications not requested yet. Alerts still appear here.", "尚未申请系统通知；提醒仍会显示在这里。")
    @Published var notificationAuthorization: UNAuthorizationStatus = .notDetermined
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
        if !writable { persistenceError = tr("Alert history could not be read. The original file was kept and will not be overwritten.", "提醒记录无法读取，已保留原文件并停止覆盖。") }
    }
    func configureNotifications() { UNUserNotificationCenter.current().delegate = self; refreshPermission() }
    func refreshPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationAuthorization = settings.authorizationStatus
                self?.notificationStatus = settings.authorizationStatus == .authorized ? tr("Notifications are allowed.", "系统通知已允许。") : settings.authorizationStatus == .denied ? tr("Notifications are off. Turn them on in System Settings; alerts still appear here.", "系统通知未允许；可在系统设置中开启，面板内提醒仍有效。") : tr("Notifications not requested yet. Alerts still appear here.", "尚未申请系统通知；提醒仍会显示在这里。")
            }
        }
    }
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.notificationStatus = tr("Notification request failed: ", "申请通知失败：") + error.localizedDescription } }
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
                    DispatchQueue.main.async { self?.deliveryError = error.map { tr("Notification failed; the alert is kept in the window: ", "系统通知发送失败，提醒已保留在面板：") + $0.localizedDescription } ?? "" }
                }
            }
        }
    }
    func summary(_ alert: DiskWriteAlert) -> String {
        switch alert.kind {
        case .sustained: return tr("Wrote \(diskVolume(alert.bytes)) in the last 10 full minutes, above the rate threshold for at least 8 of them.", "最近 10 个完整分钟写入 \(diskVolume(alert.bytes))，其中至少 8 分钟达到速率阈值。")
        case .hourly: return tr("Wrote \(diskVolume(alert.bytes)) in the last hour, reaching the budget.", "最近一小时已观测写入 \(diskVolume(alert.bytes))，达到设置预算。")
        case .daily: return tr("Wrote \(diskVolume(alert.bytes)) today, reaching the budget.", "今日已观测写入 \(diskVolume(alert.bytes))，达到设置预算。")
        }
    }
    func snooze(_ path: String) { preferences.snoozedUntil[path] = Date().addingTimeInterval(3600) }
    enum AppState: Hashable { case active, snoozed, ignored }
    // One control for per-app muting so "ignore", "snooze" and "resume" never disagree.
    func state(for path: String) -> AppState {
        if preferences.ignored.contains(path) { return .ignored }
        if let until = preferences.snoozedUntil[path], until > Date() { return .snoozed }
        return .active
    }
    func setState(_ state: AppState, for path: String) {
        var value = preferences
        value.ignored.remove(path); value.snoozedUntil.removeValue(forKey: path)
        if state == .ignored { value.ignored.insert(path) }
        if state == .snoozed { value.snoozedUntil[path] = Date().addingTimeInterval(3600) }
        preferences = value
    }
    func save() {
        guard writable else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(memory).write(to: file, options: .atomic); persistenceError = ""
        } catch { persistenceError = tr("Could not save alerts: ", "提醒保存失败：") + error.localizedDescription }
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
