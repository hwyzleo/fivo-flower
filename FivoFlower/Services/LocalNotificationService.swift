import Foundation
import UserNotifications

/// 系统通知调度。提醒记录是事实源，通知只是镜像；
/// 启动与前台恢复时通过 reconcile 对齐。
final class LocalNotificationService: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(_ reminder: CareReminder) async {
        guard reminder.status == .pending else {
            await cancel(identifier: reminder.notificationIdentifier)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = "该记录养护啦，完成后可在日历中打卡。"
        content.sound = .default
        content.userInfo = ["reminderID": reminder.id.uuidString]

        let calendar = FivoDate.defaultCalendar
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.dueAt)
        let trigger: UNNotificationTrigger
        if reminder.dueAt <= Date() {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        } else {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: reminder.notificationIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func cancel(identifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func reconcile(_ reminders: [CareReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let desired = Dictionary(
            uniqueKeysWithValues: reminders
                .filter { $0.status == .pending }
                .map { ($0.notificationIdentifier, $0) }
        )
        let stale = pending.map(\.identifier).filter { desired[$0] == nil }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
        let scheduled = Set(pending.map(\.identifier))
        for (identifier, reminder) in desired where !scheduled.contains(identifier) {
            await schedule(reminder)
        }
    }
}
